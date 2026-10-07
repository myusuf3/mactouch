#include "keyboard.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "tusb.h"

#include "typing.h"
#include "usb_descriptors.h"

// How long the host gets to take each report. It polls every 10 ms; this
// also covers a host busy with the card at the lock screen. Counted in whole
// ticks, since at 100 Hz any wait shorter than 10 ms rounds to none.
#define REPORT_WAIT_MS 500

static bool port_ready(void *ctx) {
  (void)ctx;
  return tud_hid_ready();
}

static bool port_send(void *ctx, typing_key_t key) {
  (void)ctx;
  uint8_t codes[6] = {key.code};
  return tud_hid_keyboard_report(0, key.modifier, key.code ? codes : NULL);
}

static void port_sleep(void *ctx) {
  (void)ctx;
  vTaskDelay(1);
}

bool keyboard_type(const typing_key_t *keys, size_t count) {
  if (!tud_mounted()) return false;
  typing_port_t port = {.ready = port_ready, .send = port_send, .sleep = port_sleep};
  unsigned max_waits = pdMS_TO_TICKS(REPORT_WAIT_MS) ? pdMS_TO_TICKS(REPORT_WAIT_MS) : 1;
  return typing_run(&port, keys, count, max_waits);
}

// TinyUSB's HID class wants these whether or not the interface is present.

uint8_t const *tud_hid_descriptor_report_cb(uint8_t instance) {
  (void)instance;
  return mactouch_keyboard_report_descriptor;
}

uint16_t tud_hid_get_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t type, uint8_t *buffer,
                               uint16_t length) {
  (void)instance; (void)report_id; (void)type; (void)buffer; (void)length;
  return 0;
}

void tud_hid_set_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t type, uint8_t const *buffer,
                           uint16_t length) {
  (void)instance; (void)report_id; (void)type; (void)buffer; (void)length;
}
