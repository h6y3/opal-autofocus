#include "copalusb.h"

struct opal_usb_device { int unused; };

kern_return_t opal_usb_open(io_service_t service, opal_usb_device_t **out) {
    (void)service; (void)out;
    return kIOReturnUnsupported;
}

kern_return_t opal_usb_request(opal_usb_device_t *dev, uint8_t bmRequestType, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex, void *data, uint16_t length,
                               uint32_t *done) {
    (void)dev; (void)bmRequestType; (void)bRequest; (void)wValue; (void)wIndex;
    (void)data; (void)length; (void)done;
    return kIOReturnUnsupported;
}

void opal_usb_close(opal_usb_device_t *dev) { (void)dev; }
