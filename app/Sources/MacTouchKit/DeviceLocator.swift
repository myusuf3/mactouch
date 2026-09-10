import Foundation
import IOKit

/// Finds the serial device node of an attached mactouch by USB vendor and
/// product ID, so a second CDC gadget on the same Mac is never mistaken for it.
public enum DeviceLocator {
  public static let vendorID = 0x303a
  public static let productID = 0x4d54

  public static func calloutPaths(vendorID: Int = vendorID, productID: Int = productID) -> [String] {
    guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else { return [] }
    matching["idVendor"] = vendorID
    matching["idProduct"] = productID
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }

    var paths: [String] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      let value = IORegistryEntrySearchCFProperty(
        service, kIOServicePlane, "IOCalloutDevice" as CFString, kCFAllocatorDefault,
        IOOptionBits(kIORegistryIterateRecursively))
      if let path = value as? String { paths.append(path) }
    }
    return paths.sorted()
  }

  /// The single attached device, or nil. Throws when more than one is present
  /// so the caller can ask the user to pick.
  public static func find() throws -> String? {
    let paths = calloutPaths()
    if paths.count > 1 { throw DeviceError.unexpected("several devices attached: \(paths.joined(separator: ", "))") }
    return paths.first
  }
}
