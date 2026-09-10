#!/usr/bin/env python
"""Boot the application from ROM download mode over USB-Serial/JTAG.

Reads the RTC "force download boot" request register, clears it if the last
firmware left it set (the ROM does not clear it, so every reset would land in
download mode again), then resets through the RTC watchdog. A plain EN pulse
over USB-Serial/JTAG leaves this board in download mode; the watchdog reset
does not. Run with the ESP-IDF python."""
import subprocess
import sys
import time

from serial.tools import list_ports

RTC_CNTL_OPTION1_REG = 0x6000812C

ports = [i.device for i in list_ports.comports() if i.vid == 0x303A and i.pid == 0x1001]
if not ports:
    print("no ROM download-mode device", file=sys.stderr)
    sys.exit(1)
port = ports[0]
base = ["esptool.py", "--chip", "esp32s3", "--port", port, "--before", "no_reset", "--after", "no_reset"]
out = subprocess.run(base + ["read_mem", hex(RTC_CNTL_OPTION1_REG)], capture_output=True, text=True).stdout
value = next((l for l in out.splitlines() if "0x6000812c" in l.lower()), out.strip().splitlines()[-1])
print("RTC_CNTL_OPTION1:", value.strip())
if "= 0x0" not in value:
    subprocess.run(base + ["write_mem", hex(RTC_CNTL_OPTION1_REG), "0", "0xffffffff"], capture_output=True)
    print("cleared force-download request")
subprocess.run(["esptool.py", "--chip", "esp32s3", "--port", port, "--before", "no_reset",
                "--after", "watchdog_reset", "chip_id"], capture_output=True)
for _ in range(40):
    time.sleep(0.5)
    devices = [(i.device, i.pid) for i in list_ports.comports() if i.vid]
    if any(pid == 0x4D54 for _, pid in devices):
        print("application booted on", [d for d, pid in devices if pid == 0x4D54][0])
        sys.exit(0)
print("application did not come up:", devices)
sys.exit(2)
