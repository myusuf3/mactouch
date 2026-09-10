#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// The ring on the sensor. Colour values are the sensor's 3-bit channel mask,
// which happens to give exactly the eight names below.
typedef enum {
  LED_OFF = 0, LED_BLUE = 1, LED_GREEN = 2, LED_CYAN = 3,
  LED_RED = 4, LED_MAGENTA = 5, LED_YELLOW = 6, LED_WHITE = 7,
} led_colour_t;

typedef enum {
  LED_MODE_OFF, LED_MODE_ON, LED_MODE_BREATHE, LED_MODE_FLASH,
  LED_MODE_FADE_IN, LED_MODE_FADE_OUT,
} led_mode_t;

void led_init(void);
// Show a state until the next call. cycles 0 means forever.
bool led_set(led_mode_t mode, led_colour_t colour, led_colour_t colour2, uint8_t cycles);
// The state the ring returns to. Persisted, applied immediately.
bool led_set_idle(led_colour_t colour);
led_colour_t led_idle_colour(void);
bool led_idle(void);
// Green or red for 350 ms, then idle. Blocks the caller.
void led_result(bool ok);

bool led_parse_colour(const char *name, led_colour_t *out);
bool led_parse_mode(const char *name, led_mode_t *out);
const char *led_colour_name(led_colour_t colour);
const char *led_mode_name(led_mode_t mode);
// "mode:colour" or "mode:colour:colour2" for STATUS.
void led_describe(char *out, size_t cap);
