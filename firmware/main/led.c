#include "led.h"

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "settings.h"
#include "zw101.h"

static const char *COLOURS[] = {"off", "blue", "green", "cyan", "red", "magenta", "yellow", "white"};
static const char *MODES[] = {"off", "on", "breathe", "flash", "fadein", "fadeout"};
static const uint8_t FUNCTIONS[] = {
  ZW101_LED_OFF, ZW101_LED_ON, ZW101_LED_BREATHE, ZW101_LED_FLASH,
  ZW101_LED_FADE_IN, ZW101_LED_FADE_OUT,
};

static led_mode_t current_mode = LED_MODE_OFF;
static led_colour_t current_colour = LED_OFF;
static led_colour_t current_colour2 = LED_OFF;

bool led_set(led_mode_t mode, led_colour_t colour, led_colour_t colour2, uint8_t cycles) {
  if (mode == LED_MODE_OFF || colour == LED_OFF) {
    mode = LED_MODE_OFF;
    colour = colour2 = LED_OFF;
  }
  bool ok = zw101_led(FUNCTIONS[mode], colour, colour2, cycles);
  if (ok) {
    current_mode = mode;
    current_colour = colour;
    current_colour2 = colour2;
  }
  return ok;
}

bool led_idle(void) {
  led_colour_t colour = settings_idle_colour();
  return led_set(colour == LED_OFF ? LED_MODE_OFF : LED_MODE_ON, colour, colour, 0);
}

bool led_set_idle(led_colour_t colour) {
  settings_set_idle_colour(colour);
  return led_idle();
}

led_colour_t led_idle_colour(void) { return settings_idle_colour(); }

void led_result(bool ok) {
  led_set(LED_MODE_ON, ok ? LED_GREEN : LED_RED, ok ? LED_GREEN : LED_RED, 0);
  vTaskDelay(pdMS_TO_TICKS(350));
  led_idle();
}

void led_init(void) { led_idle(); }

bool led_parse_colour(const char *name, led_colour_t *out) {
  for (unsigned i = 0; i < sizeof(COLOURS) / sizeof(COLOURS[0]); i++) {
    if (strcmp(name, COLOURS[i]) == 0) { *out = (led_colour_t)i; return true; }
  }
  return false;
}

bool led_parse_mode(const char *name, led_mode_t *out) {
  for (unsigned i = 0; i < sizeof(MODES) / sizeof(MODES[0]); i++) {
    if (strcmp(name, MODES[i]) == 0) { *out = (led_mode_t)i; return true; }
  }
  return false;
}

const char *led_colour_name(led_colour_t colour) { return COLOURS[colour & 7]; }
const char *led_mode_name(led_mode_t mode) { return MODES[mode]; }

void led_describe(char *out, size_t cap) {
  if (current_colour2 != current_colour) {
    snprintf(out, cap, "%s:%s:%s", MODES[current_mode], COLOURS[current_colour], COLOURS[current_colour2]);
  } else {
    snprintf(out, cap, "%s:%s", MODES[current_mode], COLOURS[current_colour]);
  }
}
