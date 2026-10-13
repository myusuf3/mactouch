#include "USBReset.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

static CFNumberRef number(int value) { return CFNumberCreate(NULL, kCFNumberIntType, &value); }

bool usb_reenumerate(uint16_t vendor, uint16_t product) {
  CFMutableDictionaryRef match = IOServiceMatching(kIOUSBDeviceClassName);
  CFNumberRef vid = number(vendor), pid = number(product);
  CFDictionarySetValue(match, CFSTR(kUSBVendorID), vid);
  CFDictionarySetValue(match, CFSTR(kUSBProductID), pid);
  CFRelease(vid);
  CFRelease(pid);
  io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);  // consumes match
  if (!service) return false;

  IOCFPlugInInterface **plugin = NULL;
  SInt32 score;
  kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                                                       &plugin, &score);
  IOObjectRelease(service);
  if (kr != KERN_SUCCESS || !plugin) return false;
  IOUSBDeviceInterface650 **device = NULL;
  (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID650), (LPVOID *)&device);
  (*plugin)->Release(plugin);
  if (!device) return false;

  // The serial and smart card drivers hold the device's interfaces; seizing
  // the device itself is enough to reset it.
  kr = (*device)->USBDeviceOpenSeize(device);
  if (kr == KERN_SUCCESS) {
    kr = (*device)->USBDeviceReEnumerate(device, 0);
    (*device)->USBDeviceClose(device);
  }
  (*device)->Release(device);
  return kr == KERN_SUCCESS;
}
