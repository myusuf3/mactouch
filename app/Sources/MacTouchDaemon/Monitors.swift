import Foundation
import MacTouchKit

enum MonitorName: String, CaseIterable {
  case lock, focus, mic, camera
}

/// The signal sources behind the policy layers. Each reports a ring state for
/// its layer, or nil to clear it. Mic and camera share the privacy layer.
final class Monitors {
  typealias Update = (RingLayer, RingState?) -> Void
  private let defaults: UserDefaults
  private let update: Update
  private let lock = ScreenLockMonitor()
  private let focus = FocusMonitor()
  private let mic = AudioInputMonitor()
  private let camera = CameraMonitor()
  private var running: Set<MonitorName> = []
  private var privacyOffTimer: DispatchWorkItem?
  private let queue = DispatchQueue(label: "mactouch.monitors")

  init(defaults: UserDefaults, update: @escaping Update) {
    self.defaults = defaults
    self.update = update
    lock.onChange = { [weak self] locked in
      log("screen \(locked ? "locked" : "unlocked")")
      self?.update(.locked, locked ? .off : nil)
    }
    focus.onChange = { [weak self] mode in
      log("focus \(mode ?? "off")")
      self?.update(.focus, mode.map { _ in .steady(.magenta) })
    }
    mic.onChange = { [weak self] _ in self?.privacyChanged() }
    camera.onChange = { [weak self] _ in self?.privacyChanged() }
  }

  // Devices flap on and off for a moment while an app opens them. Going red
  // is immediate; going back is held for a second so the ring does not flicker.
  private func privacyChanged() {
    let active = (running.contains(.mic) && mic.isActive) || (running.contains(.camera) && camera.isActive)
    log("privacy mic=\(mic.isActive) camera=\(camera.isActive)")
    queue.async {
      self.privacyOffTimer?.cancel()
      if active {
        self.privacyOffTimer = nil
        self.update(.privacy, RingState(.breathe, .red))
      } else {
        let off = DispatchWorkItem { self.update(.privacy, nil) }
        self.privacyOffTimer = off
        self.queue.asyncAfter(deadline: .now() + 1, execute: off)
      }
    }
  }

  func start() {
    for name in MonitorName.allCases where isEnabled(name) { startMonitor(name) }
  }

  private func startMonitor(_ name: MonitorName) {
    guard !running.contains(name) else { return }
    running.insert(name)
    switch name {
    case .lock: lock.start()
    case .focus: focus.start(); log("focus monitor source=\(focus.source.rawValue)")
    case .mic: mic.start()
    case .camera: camera.start()
    }
  }

  private func stopMonitor(_ name: MonitorName) {
    guard running.contains(name) else { return }
    running.remove(name)
    switch name {
    case .lock: lock.stop(); update(.locked, nil)
    case .focus: focus.stop(); update(.focus, nil)
    case .mic: mic.stop(); privacyChanged()
    case .camera: camera.stop(); privacyChanged()
    }
  }

  func isEnabled(_ name: MonitorName) -> Bool {
    defaults.object(forKey: "monitor.\(name.rawValue)") as? Bool ?? true
  }

  var enabledNames: [String] { MonitorName.allCases.filter(isEnabled).map(\.rawValue) }

  func set(_ name: MonitorName, enabled: Bool) {
    defaults.set(enabled, forKey: "monitor.\(name.rawValue)")
    if enabled { startMonitor(name) } else { stopMonitor(name) }
  }
}
