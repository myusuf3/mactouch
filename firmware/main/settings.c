#include "settings.h"

#include <string.h>

#include "esp_log.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "nvs.h"

static const char *TAG = "settings";
static nvs_handle_t nvs;
static uint8_t idle_colour = 1;  // blue
static touch_source_t touch_source = TOUCH_SOURCE_PIN;
static uint8_t device_key[32];
static bool key_loaded;

void settings_init(void) {
  ESP_ERROR_CHECK(nvs_open("mactouch", NVS_READWRITE, &nvs));
  uint8_t value;
  if (nvs_get_u8(nvs, "idle", &value) == ESP_OK) idle_colour = value;
  if (nvs_get_u8(nvs, "touch", &value) == ESP_OK) touch_source = (touch_source_t)value;
  size_t len = sizeof(device_key);
  if (nvs_get_blob(nvs, "devkey", device_key, &len) == ESP_OK && len == sizeof(device_key)) {
    key_loaded = true;
  } else {
    esp_fill_random(device_key, sizeof(device_key));
    ESP_ERROR_CHECK(nvs_set_blob(nvs, "devkey", device_key, sizeof(device_key)));
    ESP_ERROR_CHECK(nvs_commit(nvs));
    key_loaded = true;
    ESP_LOGI(TAG, "generated device key");
  }
}

uint8_t settings_idle_colour(void) { return idle_colour; }

void settings_set_idle_colour(uint8_t colour) {
  idle_colour = colour;
  nvs_set_u8(nvs, "idle", colour);
  nvs_commit(nvs);
}

touch_source_t settings_touch_source(void) { return touch_source; }

void settings_set_touch_source(touch_source_t source) {
  touch_source = source;
  nvs_set_u8(nvs, "touch", (uint8_t)source);
  nvs_commit(nvs);
}

void settings_device_key(uint8_t out[32]) {
  configASSERT(key_loaded);
  memcpy(out, device_key, sizeof(device_key));
}
