#include "copalusb.h"

#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

struct opal_usb_device {
    IOUSBDeviceInterface **iface;
};

kern_return_t opal_usb_open(io_service_t service, opal_usb_device_t **out) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS) return kr;
    if (plugin == NULL) return kIOReturnNoDevice;

    IOUSBDeviceInterface **iface = NULL;
    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&iface);
    (*plugin)->Release(plugin);
    if (hr != S_OK || iface == NULL) return kIOReturnNotFound;

    opal_usb_device_t *dev = calloc(1, sizeof *dev);
    if (dev == NULL) {
        (*iface)->Release(iface);
        return kIOReturnNoMemory;
    }
    dev->iface = iface;
    *out = dev;
    return KERN_SUCCESS;
}

kern_return_t opal_usb_request(opal_usb_device_t *dev, uint8_t bmRequestType, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex, void *data, uint16_t length,
                               uint32_t *done) {
    IOUSBDevRequest req = {
        .bmRequestType = bmRequestType,
        .bRequest = bRequest,
        .wValue = wValue,
        .wIndex = wIndex,
        .wLength = length,
        .pData = data,
        .wLenDone = 0,
    };
    kern_return_t kr = (*dev->iface)->DeviceRequest(dev->iface, &req);
    if (done) *done = req.wLenDone;
    return kr;
}

void opal_usb_close(opal_usb_device_t *dev) {
    if (dev == NULL) return;
    if (dev->iface) (*dev->iface)->Release(dev->iface);
    free(dev);
}
