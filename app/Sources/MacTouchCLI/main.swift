import Foundation
import MacTouchKit

// mactouch: command line for the device. Talks to mactouchd over its socket
// when the daemon is running, otherwise straight to the serial port.

let usage = """
usage: mactouch [--direct] [--port /dev/cu.usbmodemXXXX] <command>

  status                          daemon, firmware, sensor, ring and touch state
  ping
  led <mode> [colour] [colour2] [--for SECONDS]
                                  mode: off on breathe flash fadein fadeout
                                  colour: off blue green cyan red magenta yellow white
  notify <colour> [--for SECONDS] [--mode MODE]
                                  temporary ring state via the daemon (default 5s)
  clear                           drop the notify layer
  idle <colour>                   the ring's resting colour (persisted on the device)
  identify [--timeout SECONDS] [--prompt COLOUR] [--nonce HEX32] [--reason TEXT]
                                  exit 0 on a match, 2 on timeout or cancel
  enroll <slot>                   1..20, follow the prompts
  delete <slot>|all
  slots
  watch on|off                    match on every touch and report it
  touch pin|poll                  how the device detects a finger
  monitor <lock|focus|mic|camera> on|off
  pair [--timeout SECONDS]        print the device key (once per boot, needs a touch)
  gpio                            pin levels, for checking wiring
  events                          stream events until interrupted
  cancel
  reboot

  --direct forces the serial port even when mactouchd is running.
"""

struct Exit: Error { let code: Int32; let message: String? }
func fail(_ message: String, code: Int32 = 1) -> Exit { Exit(code: code, message: message) }

struct Options {
  var direct = false
  var port: String?
  var command: [String]
}

func parse(_ arguments: [String]) throws -> Options {
  var args = arguments
  var options = Options(command: [])
  while let first = args.first, first.hasPrefix("--") {
    switch first {
    case "--direct": options.direct = true; args.removeFirst()
    case "--port":
      guard args.count >= 2 else { throw fail("--port needs a path") }
      options.port = args[1]; options.direct = true; args.removeFirst(2)
    case "--help", "-h": throw Exit(code: 0, message: usage)
    default: throw fail("unknown option \(first)\n\(usage)")
    }
  }
  guard !args.isEmpty else { throw Exit(code: 2, message: usage) }
  options.command = args
  return options
}

func option(_ name: String, in args: inout [String]) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  let value = args[index + 1]
  args.removeSubrange(index...index + 1)
  return value
}

func colour(_ text: String) throws -> LEDColour {
  guard let value = LEDColour(rawValue: text) else { throw fail("unknown colour \(text)") }
  return value
}

func printFields(_ fields: Fields) {
  for key in fields.values.keys.sorted() { print("\(key)=\(fields.values[key]!)") }
  if !fields.positional.isEmpty { print(fields.positional.joined(separator: " ")) }
}

func printEvent(_ name: String, _ fields: Fields) {
  let extra = fields.values.keys.sorted().map { "\($0)=\(fields.values[$0]!)" }.joined(separator: " ")
  FileHandle.standardError.write(Data("  \(name) \(extra)\n".utf8))
}

// MARK: via the daemon

func runViaDaemon(_ command: [String]) throws -> Int32 {
  var args = Array(command.dropFirst())
  let verb = command[0]
  var request = ControlRequest(verb: verb)
  var timeout: TimeInterval = 10

  switch verb {
  case "status", "ping", "clear", "slots", "gpio", "cancel", "reboot":
    break
  case "led":
    if let seconds = option("--for", in: &args) { request.values["for"] = seconds }
    request.positional = args
  case "notify":
    request.values["for"] = option("--for", in: &args) ?? "5"
    if let mode = option("--mode", in: &args) { request.values["mode"] = mode }
    request.positional = args
  case "idle", "watch", "touch", "monitor":
    request.positional = args
  case "identify":
    let seconds = Double(option("--timeout", in: &args) ?? "15") ?? 15
    request.values["timeout"] = String(seconds)
    if let prompt = option("--prompt", in: &args) { request.values["prompt"] = prompt }
    if let nonce = option("--nonce", in: &args) { request.values["nonce"] = nonce }
    if let reason = option("--reason", in: &args) { request.values["reason"] = reason }
    timeout = seconds + 6
  case "enroll":
    guard let slot = args.first else { throw fail("enroll needs a slot number") }
    request.values["slot"] = slot
    timeout = 55
    print("touch the sensor, lift, then touch again")
  case "delete":
    guard let target = args.first else { throw fail("delete needs a slot number or all") }
    if target == "all" { request.positional = ["all"] } else { request.values["slot"] = target }
  case "pair":
    let seconds = Double(option("--timeout", in: &args) ?? "30") ?? 30
    request.values["timeout"] = String(seconds)
    timeout = seconds + 6
    print("touch the sensor to release the device key")
  case "events":
    let client = try ControlClient()
    try client.send("events")
    FileHandle.standardError.write(Data("streaming events from mactouchd, ctrl-c to stop\n".utf8))
    while true {
      guard let line = try client.readLine(timeout: 3600) else { continue }
      if case .evt(let name, let fields)? = ControlLine.parse(line) { printEvent(name, fields) }
    }
  default:
    throw fail("unknown command \(verb)\n\(usage)")
  }

  let client = try ControlClient()
  defer { client.close() }
  do {
    printFields(try client.request(request, timeout: timeout, onEvent: printEvent))
  } catch ControlError.rejected(_, let reason) where verb == "identify" && (reason == "timeout" || reason == "cancelled") {
    throw Exit(code: 2, message: reason)
  }
  return 0
}

// MARK: directly over serial

func openDevice(_ port: String?) throws -> Device {
  do {
    if let port { return try Device(path: port) }
    return try Device()
  } catch DeviceError.openFailed(let path, let code) where code == EBUSY {
    throw fail("\(path) is held by another process, probably mactouchd; stop it or drop --direct")
  }
}

func runDirect(_ command: [String], port: String?) throws -> Int32 {
  var args = Array(command.dropFirst())
  let device = try openDevice(port)
  device.onEvent = printEvent
  device.onDisconnect = {
    FileHandle.standardError.write(Data("device disconnected\n".utf8))
    exit(1)
  }

  switch command[0] {
  case "status": printFields(try device.request(.status))
  case "ping": printFields(try device.request(.ping))
  case "led":
    guard let modeText = args.first, let mode = LEDMode(rawValue: modeText) else { throw fail("led needs a mode") }
    var first = LEDColour.off, second: LEDColour? = nil
    if mode != .off {
      guard args.count >= 2 else { throw fail("led needs a colour") }
      first = try colour(args[1])
      if args.count >= 3 { second = try colour(args[2]) }
    }
    try device.request(.led(mode, first, second))
  case "idle":
    guard let text = args.first else { throw fail("idle needs a colour") }
    try device.request(.idle(try colour(text)))
  case "identify":
    let seconds = Double(option("--timeout", in: &args) ?? "15") ?? 15
    let prompt = try option("--prompt", in: &args).map(colour)
    let nonce = option("--nonce", in: &args)
    _ = option("--reason", in: &args)
    do {
      printFields(try device.request(.identify(timeoutMs: Int(seconds * 1000), prompt: prompt, nonce: nonce), timeout: seconds + 3))
    } catch DeviceError.rejected(_, let reason) where reason == "timeout" || reason == "cancelled" {
      throw Exit(code: 2, message: reason)
    }
  case "enroll":
    guard let slot = args.first.flatMap(Int.init) else { throw fail("enroll needs a slot number") }
    print("touch the sensor, lift, then touch again")
    printFields(try device.request(.enroll(slot: slot), timeout: 45))
  case "delete":
    if args.first == "all" { try device.request(.deleteAll) }
    else if let slot = args.first.flatMap(Int.init) { try device.request(.delete(slot: slot)) }
    else { throw fail("delete needs a slot number or all") }
  case "slots": printFields(try device.request(.slots))
  case "watch":
    guard let value = args.first, value == "on" || value == "off" else { throw fail("watch on|off") }
    try device.request(.watch(value == "on"))
  case "touch":
    guard let value = args.first.flatMap(TouchSource.init) else { throw fail("touch pin|poll") }
    try device.request(.touch(value))
  case "pair":
    let seconds = Double(option("--timeout", in: &args) ?? "30") ?? 30
    print("touch the sensor to release the device key")
    printFields(try device.request(.pair(timeoutMs: Int(seconds * 1000)), timeout: seconds + 3))
  case "gpio": printFields(try device.request(.gpio))
  case "events":
    FileHandle.standardError.write(Data("streaming events from the device, ctrl-c to stop\n".utf8))
    dispatchMain()
  case "cancel": try device.request(.cancel)
  case "reboot": try device.request(.reboot)
  case "notify", "clear", "monitor":
    throw fail("\(command[0]) needs mactouchd running")
  default:
    throw fail("unknown command \(command[0])\n\(usage)")
  }
  return 0
}

setlinebuf(stdout)
do {
  let options = try parse(Array(CommandLine.arguments.dropFirst()))
  if !options.direct && ControlClient.isAvailable() {
    exit(try runViaDaemon(options.command))
  }
  exit(try runDirect(options.command, port: options.port))
} catch let exit as Exit {
  if let message = exit.message {
    if exit.code == 0 { print(message) } else { FileHandle.standardError.write(Data((message + "\n").utf8)) }
  }
  Foundation.exit(exit.code)
} catch {
  FileHandle.standardError.write(Data("mactouch: \(error)\n".utf8))
  Foundation.exit(1)
}
