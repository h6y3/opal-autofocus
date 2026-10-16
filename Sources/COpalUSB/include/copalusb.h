#ifndef COPALUSB_H
#define COPALUSB_H

#include <stdint.h>
#include <IOKit/IOKitLib.h>

typedef struct opal_usb_device opal_usb_device_t;

kern_return_t opal_usb_open(io_service_t service, opal_usb_device_t **out);
kern_return_t opal_usb_request(opal_usb_device_t *dev, uint8_t bmRequestType, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex, void *data, uint16_t length,
                               uint32_t *done);
void opal_usb_close(opal_usb_device_t *dev);

#endif
