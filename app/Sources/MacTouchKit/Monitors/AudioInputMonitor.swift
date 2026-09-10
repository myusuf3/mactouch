import CoreAudio
import Foundation

/// Reports when any audio input device is in use by some process, which is
/// the closest CoreAudio gets to "the microphone is live".
public final class AudioInputMonitor {
  public var onChange: ((Bool) -> Void)?
  public private(set) var isActive = false

  private let queue = DispatchQueue(label: "mactouch.audio")
  private var watched: Set<AudioDeviceID> = []
  private var listenerBlock: AudioObjectPropertyListenerBlock!
  private var devicesBlock: AudioObjectPropertyListenerBlock!

  public init() {}

  private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  public func start() {
    listenerBlock = { [weak self] _, _ in self?.queue.async { self?.evaluate() } }
    devicesBlock = { [weak self] _, _ in self?.queue.async { self?.refreshDevices() } }
    var devices = AudioInputMonitor.address(kAudioHardwarePropertyDevices)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, queue, devicesBlock)
    queue.async { self.refreshDevices() }
  }

  public func stop() {
    queue.sync {
      var devices = AudioInputMonitor.address(kAudioHardwarePropertyDevices)
      AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, queue, devicesBlock)
      var running = AudioInputMonitor.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
      for id in watched { AudioObjectRemovePropertyListenerBlock(id, &running, queue, listenerBlock) }
      watched.removeAll()
    }
  }

  private func inputDevices() -> [AudioDeviceID] {
    var address = AudioInputMonitor.address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter { id in
      var streams = AudioInputMonitor.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
      var streamSize: UInt32 = 0
      return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
    }
  }

  private func refreshDevices() {
    var running = AudioInputMonitor.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
    let current = Set(inputDevices())
    for id in watched.subtracting(current) { AudioObjectRemovePropertyListenerBlock(id, &running, queue, listenerBlock) }
    for id in current.subtracting(watched) { AudioObjectAddPropertyListenerBlock(id, &running, queue, listenerBlock) }
    watched = current
    evaluate()
  }

  private func evaluate() {
    var running = AudioInputMonitor.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
    let active = watched.contains { id in
      var value: UInt32 = 0
      var size = UInt32(MemoryLayout<UInt32>.size)
      return AudioObjectGetPropertyData(id, &running, 0, nil, &size, &value) == noErr && value != 0
    }
    guard active != isActive else { return }
    isActive = active
    onChange?(active)
  }
}
