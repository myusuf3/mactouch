idf_component_register(
  SRCS
    "main.c"
    "zw101.c"
    "led.c"
    "touch.c"
    "link.c"
    "usb.c"
    "usb_descriptors.c"
    "ccid.c"
    "piv.c"
    "presence.c"
    "fw_update.c"
    "settings.c"
  INCLUDE_DIRS "."
  REQUIRES app_update bootloader_support esp_tinyusb esp_timer nvs_flash mbedtls
  PRIV_REQUIRES esp_driver_uart esp_driver_gpio
)

# `idf.py -B build-crash -DMACTOUCH_CRASH_TEST=1 build` makes an image that
# aborts a few seconds after boot, for checking that rollback works.
if(MACTOUCH_CRASH_TEST)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE MACTOUCH_CRASH_TEST=1)
endif()

target_compile_definitions(${COMPONENT_LIB} PRIVATE
  MACTOUCH_FW_VERSION="${MACTOUCH_VERSION}"
  MACTOUCH_PROTOCOL_VERSION=1
)
