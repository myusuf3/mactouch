import Foundation

/// Reports the active Focus mode. Preferred source is the Do Not Disturb
/// assertion store in the user's Library, which names the mode but is behind
/// Full Disk Access. Without that permission it falls back to polling whether
/// Control Center is showing the Focus menu bar item, which macOS does by
/// default only while a Focus is active; that source cannot name the mode.
public final class FocusMonitor {
  public enum Source: String { case assertions, menubar }
  /// Mode identifier such as `com.apple.donotdisturb.mode.default`, `focus`
  /// when only the fallback is available, or nil.
  public var onChange: ((String?) -> Void)?
  public private(set) var activeMode: String?
  public private(set) var source: Source = .assertions
  private var pollTimer: DispatchSourceTimer?

  private let directory: String
  private let queue = DispatchQueue(label: "mactouch.focus")
  private var directorySource: DispatchSourceFileSystemObject?
  private var fileSource: DispatchSourceFileSystemObject?
  private var directoryFD: Int32 = -1
  private var fileFD: Int32 = -1

  public init(home: String = NSHomeDirectory()) {
    directory = home + "/Library/DoNotDisturb/DB"
  }

  public func start() {
    directoryFD = open(directory, O_EVTONLY)
    guard directoryFD >= 0, FileManager.default.isReadableFile(atPath: directory + "/Assertions.json") else {
      if directoryFD >= 0 { close(directoryFD); directoryFD = -1 }
      startMenuBarFallback()
      return
    }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: directoryFD, eventMask: [.write, .rename], queue: queue)
    source.setEventHandler { [weak self] in self?.reload() }
    source.setCancelHandler { [fd = directoryFD] in close(fd) }
    directorySource = source
    source.resume()
    watchFile()
    reload()
  }

  public func stop() {
    directorySource?.cancel(); directorySource = nil
    fileSource?.cancel(); fileSource = nil
    pollTimer?.cancel(); pollTimer = nil
  }

  private func startMenuBarFallback() {
    source = .menubar
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: 3)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let visible = CFPreferencesCopyAppValue("NSStatusItem Visible FocusModes" as CFString,
                                              "com.apple.controlcenter" as CFString) as? Bool ?? false
      let mode: String? = visible ? "focus" : nil
      guard mode != self.activeMode else { return }
      self.activeMode = mode
      self.onChange?(mode)
    }
    pollTimer = timer
    timer.resume()
  }

  private func watchFile() {
    fileSource?.cancel()
    fileSource = nil
    fileFD = open(directory + "/Assertions.json", O_EVTONLY)
    guard fileFD >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileFD, eventMask: [.write, .delete, .rename], queue: queue)
    source.setEventHandler { [weak self] in
      self?.reload()
      // The file is replaced, not rewritten; follow the new inode.
      self?.watchFile()
    }
    source.setCancelHandler { [fd = fileFD] in close(fd) }
    fileSource = source
    source.resume()
  }

  private func reload() {
    let mode = FocusMonitor.parse(path: directory + "/Assertions.json")
    guard mode != activeMode else { return }
    activeMode = mode
    onChange?(mode)
  }

  /// The mode identifier of the first assertion record, if any.
  public static func parse(path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let entries = root["data"] as? [[String: Any]] else { return nil }
    for entry in entries {
      guard let records = entry["storeAssertionRecords"] as? [[String: Any]], let first = records.first else { continue }
      let details = first["assertionDetails"] as? [String: Any]
      return details?["assertionDetailsModeIdentifier"] as? String ?? "unknown"
    }
    return nil
  }
}
