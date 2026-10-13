import Foundation
import IOKit

/// Finds the serial device node of an attached mactouch by USB vendor and
/// product ID, so a second CDC gadget on the same Mac is never mistaken for it.
public enum DeviceLocator {
  public static let vendorID = 0x303a
  public static let productID = 0x4d54

  /// An attached board: its serial device node and its USB serial number,
  /// which the firmware derives from the chip so it tells boards apart.
  public struct Attached: Equatable, Sendable {
    public let path: String
    public let serial: String?
  }

  public static func calloutPaths(vendorID: Int = vendorID, productID: Int = productID) -> [String] {
    attached(vendorID: vendorID, productID: productID).map(\.path)
  }

  public static func attached(vendorID: Int = vendorID, productID: Int = productID) -> [Attached] {
    guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else { return [] }
    matching["idVendor"] = vendorID
    matching["idProduct"] = productID
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }

    var boards: [Attached] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      let value = IORegistryEntrySearchCFProperty(
        service, kIOServicePlane, "IOCalloutDevice" as CFString, kCFAllocatorDefault,
        IOOptionBits(kIORegistryIterateRecursively))
      guard let path = value as? String else { continue }
      let serial = IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? String
      boards.append(Attached(path: path, serial: serial))
    }
    return boards.sorted { $0.path < $1.path }
  }

  /// The single attached device, or nil. Throws when more than one is present
  /// so the caller can ask the user to pick.
  public static func find() throws -> String? {
    let paths = calloutPaths()
    if paths.count > 1 { throw DeviceError.unexpected("several devices attached: \(paths.joined(separator: ", "))") }
    return paths.first
  }
}
