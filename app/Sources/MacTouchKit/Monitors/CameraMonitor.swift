import CoreMediaIO
import Foundation

/// Reports when any camera is in use by some process.
public final class CameraMonitor {
  public var onChange: ((Bool) -> Void)?
  public private(set) var isActive = false

  private let queue = DispatchQueue(label: "mactouch.camera")
  private var watched: Set<CMIOObjectID> = []
  private var listenerBlock: CMIOObjectPropertyListenerBlock!
  private var devicesBlock: CMIOObjectPropertyListenerBlock!

  public init() {}

  private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(selector),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
  }

  public func start() {
    listenerBlock = { [weak self] _, _ in self?.queue.async { self?.evaluate() } }
    devicesBlock = { [weak self] _, _ in self?.queue.async { self?.refreshDevices() } }
    var devices = CameraMonitor.address(kCMIOHardwarePropertyDevices)
    CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devices, queue, devicesBlock)
    queue.async { self.refreshDevices() }
  }

  public func stop() {
    queue.sync {
      var devices = CameraMonitor.address(kCMIOHardwarePropertyDevices)
      CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devices, queue, devicesBlock)
      var running = CameraMonitor.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
      for id in watched { CMIOObjectRemovePropertyListenerBlock(id, &running, queue, listenerBlock) }
      watched.removeAll()
    }
  }

  private func devices() -> [CMIOObjectID] {
    var address = CameraMonitor.address(kCMIOHardwarePropertyDevices)
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr else { return [] }
    return ids
  }

  private func refreshDevices() {
    var running = CameraMonitor.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
    let current = Set(devices())
    for id in watched.subtracting(current) { CMIOObjectRemovePropertyListenerBlock(id, &running, queue, listenerBlock) }
    for id in current.subtracting(watched) { CMIOObjectAddPropertyListenerBlock(id, &running, queue, listenerBlock) }
    watched = current
    evaluate()
  }

  private func evaluate() {
    var running = CameraMonitor.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
    let active = watched.contains { id in
      var value: UInt32 = 0
      var used: UInt32 = 0
      return CMIOObjectGetPropertyData(id, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr && value != 0
    }
    guard active != isActive else { return }
    isActive = active
    onChange?(active)
  }
}
