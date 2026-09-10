#!/usr/bin/env python
"""Wait for an ESP32-S3 in ROM download mode and print its port.
The ROM enumerates as USB-Serial/JTAG (PID 0x1001) or, when the USB-OTG PHY
was kept alive across the reset, as its own CDC device (PID 0x0009 on the S3,
0x0002 on the S2). Run with the ESP-IDF python."""
import sys
import time

from serial.tools import list_ports

ROM_PIDS = {0x1001, 0x0009, 0x0002}

deadline = time.time() + (float(sys.argv[1]) if len(sys.argv) > 1 else 1800)
while time.time() < deadline:
    for info in list_ports.comports():
        if info.vid == 0x303A and info.pid in ROM_PIDS:
            print(info.device)
            sys.exit(0)
    time.sleep(0.2)
print("timed out", file=sys.stderr)
sys.exit(3)
