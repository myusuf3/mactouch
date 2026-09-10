import Foundation
import MacTouchKit

// mactouch: command line for the device. Phase 1 talks to the serial port
// directly; later phases route through the menu bar app's control socket.

let usage = """
usage: mactouch [--port /dev/cu.usbmodemXXXX] <command>

  status                          firmware, sensor, ring and touch state
  ping
  led <mode> [colour] [colour2] [cycles]
                                  mode: off on breathe flash fadein fadeout
                                  colour: off blue green cyan red magenta yellow white
  idle <colour>                   the ring's resting colour (persisted)
  identify [--timeout SECONDS] [--prompt COLOUR] [--nonce HEX32]
                                  exit 0 on a match, 2 on timeout or cancel
  enroll <slot>                   1..20, follow the prompts
  delete <slot>|all
  slots
  watch on|off                    match on every touch and report EVT MATCH
  touch pin|poll                  how the device detects a finger
  pair [--timeout SECONDS]        print the device key (once per boot, needs a touch)
  gpio                            pin levels, for checking wiring
  events                          stream device events until interrupted
  cancel
  reboot
  bootloader                      reboot into download mode for idf.py flash
"""

struct Exit: Error { let code: Int32; let message: String? }

func fail(_ message: String, code: Int32 = 1) -> Exit { Exit(code: code, message: message) }

func parse(_ arguments: [String]) throws -> (port: String?, command: [String]) {
  var args = arguments
  var port: String?
  while let first = args.first, first.hasPrefix("--") {
    switch first {
    case "--port":
      guard args.count >= 2 else { throw fail("--port needs a path") }
      port = args[1]
      args.removeFirst(2)
    case "--help", "-h":
      throw Exit(code: 0, message: usage)
    default:
      throw fail("unknown option \(first)\n\(usage)")
    }
  }
  guard !args.isEmpty else { throw Exit(code: 2, message: usage) }
  return (port, args)
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

func openDevice(_ port: String?) throws -> Device {
  if let port { return try Device(path: port) }
  return try Device()
}

func run() throws -> Int32 {
  let (port, command) = try parse(Array(CommandLine.arguments.dropFirst()))
  var args = Array(command.dropFirst())
  let device = try openDevice(port)
  device.onEvent = { name, fields in
    let extra = fields.values.keys.sorted().map { "\($0)=\(fields.values[$0]!)" }.joined(separator: " ")
    FileHandle.standardError.write(Data("  \(name) \(extra)\n".utf8))
  }
  device.onDisconnect = {
    FileHandle.standardError.write(Data("device disconnected\n".utf8))
    exit(1)
  }

  switch command[0] {
  case "status":
    printFields(try device.request(.status))
  case "ping":
    printFields(try device.request(.ping))
  case "led":
    guard let modeText = args.first, let mode = LEDMode(rawValue: modeText) else { throw fail("led needs a mode") }
    var first = LEDColour.off, second: LEDColour? = nil, cycles = 0
    if mode != .off {
      guard args.count >= 2 else { throw fail("led needs a colour") }
      first = try colour(args[1])
      if args.count >= 3 { second = try colour(args[2]) }
      if args.count >= 4 { cycles = Int(args[3]) ?? 0 }
    }
    try device.request(.led(mode, first, second, cycles: cycles))
  case "idle":
    guard let text = args.first else { throw fail("idle needs a colour") }
    try device.request(.idle(try colour(text)))
  case "identify":
    let seconds = Double(option("--timeout", in: &args) ?? "15") ?? 15
    let prompt = try option("--prompt", in: &args).map(colour)
    let nonce = option("--nonce", in: &args)
    let timeoutMs = Int(seconds * 1000)
    do {
      let fields = try device.request(
        .identify(timeoutMs: timeoutMs, prompt: prompt, nonce: nonce), timeout: seconds + 3)
      printFields(fields)
    } catch DeviceError.rejected(_, let reason) where reason == "timeout" || reason == "cancelled" {
      throw Exit(code: 2, message: reason)
    }
  case "enroll":
    guard let slot = args.first.flatMap(Int.init) else { throw fail("enroll needs a slot number") }
    print("touch the sensor, lift, then touch again")
    printFields(try device.request(.enroll(slot: slot), timeout: 45))
  case "delete":
    if args.first == "all" {
      try device.request(.deleteAll)
    } else if let slot = args.first.flatMap(Int.init) {
      try device.request(.delete(slot: slot))
    } else {
      throw fail("delete needs a slot number or all")
    }
  case "slots":
    printFields(try device.request(.slots))
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
  case "gpio":
    printFields(try device.request(.gpio))
  case "events":
    FileHandle.standardError.write(Data("streaming events, ctrl-c to stop\n".utf8))
    dispatchMain()
  case "cancel":
    try device.request(.cancel)
  case "reboot":
    try device.request(.reboot)
  case "bootloader":
    try device.request(.bootloader)
  default:
    throw fail("unknown command \(command[0])\n\(usage)")
  }
  return 0
}

setlinebuf(stdout)
do {
  exit(try run())
} catch let exit as Exit {
  if let message = exit.message {
    if exit.code == 0 { print(message) } else { FileHandle.standardError.write(Data((message + "\n").utf8)) }
  }
  Foundation.exit(exit.code)
} catch {
  FileHandle.standardError.write(Data("mactouch: \(error)\n".utf8))
  Foundation.exit(1)
}
