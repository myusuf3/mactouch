#pragma once

#include <stdbool.h>
#include <stdint.h>

// ZW101-class fingerprint module over UART. Every call takes the sensor lock;
// wrap a multi-step sequence in zw101_lock/zw101_unlock (recursive) so another
// task cannot interleave commands.

#define ZW101_MAX_SLOTS 20

#define ZW101_CONFIRM_OK 0x00
#define ZW101_CONFIRM_NO_FINGER 0x02
#define ZW101_CONFIRM_NO_MATCH 0x09

// Ring control (command 0x3C) functions and colour bits.
#define ZW101_LED_BREATHE 1
#define ZW101_LED_FLASH 2
#define ZW101_LED_ON 3
#define ZW101_LED_OFF 4
#define ZW101_LED_FADE_IN 5
#define ZW101_LED_FADE_OUT 6

void zw101_init(void);
bool zw101_ready(void);
bool zw101_recover(void);

bool zw101_lock(uint32_t timeout_ms);
void zw101_unlock(void);

bool zw101_led(uint8_t function, uint8_t start_colour, uint8_t end_colour, uint8_t cycles);

// Returns the confirm code: 0x00 finger captured, 0x02 no finger. -1 on a
// transport failure.
int zw101_get_image(void);
bool zw101_gen_char(uint8_t buffer);
// true on a match. *error is set when the sensor did not answer properly, as
// opposed to answering "no match".
bool zw101_search(uint8_t buffer, uint16_t *slot, uint16_t *score, bool *error);
bool zw101_reg_model(void);
bool zw101_store(uint8_t buffer, uint16_t slot);
bool zw101_delete(uint16_t slot);
bool zw101_delete_all(void);
// Number of stored templates, -1 on failure.
int zw101_count(void);
// Bit n set means slot n holds a template (n in 1..ZW101_MAX_SLOTS).
bool zw101_index_table(uint32_t *used);

bool zw101_touch_pin(void);

// One capture attempt: 1 match (slot/score set), 0 finger read but no match,
// 2 no finger on the sensor, -1 transport failure.
int zw101_match_now(uint16_t *slot, uint16_t *score);
