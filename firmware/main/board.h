#pragma once

// Seeed XIAO ESP32-S3. Numbers are ESP32-S3 GPIOs, comments are XIAO labels.
//
// The reference tinytouch build wires the sensor UART to D6/D7 (GPIO43/44).
// This board was assembled differently, and the pin sweep confirmed the UART
// pair below. The ESP32-S3 GPIO matrix lets any pin carry UART, so wiring
// differences are a three-line change here and nowhere else.

#define BOARD_FP_TX_PIN 1     // D0 -> sensor RX (sensor pin 5)
#define BOARD_FP_RX_PIN 2     // D1 <- sensor TX (sensor pin 4)
#define BOARD_FP_TOUCH_PIN 4  // D3 <- sensor TouchOut (sensor pin 2); high while touched. Unconfirmed on this board.
#define BOARD_FP_UART_NUM 1
#define BOARD_FP_BAUD 57600

#define BOARD_USER_LED_PIN 21 // on-board yellow LED, active low
