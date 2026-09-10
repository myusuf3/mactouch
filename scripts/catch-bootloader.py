#!/usr/bin/env python
"""Put a board into ROM download mode without touching BOOT.

While tinyTouch (or any TinyUSB firmware) runs, esptool cannot reset the chip.
But between power-on and the app starting TinyUSB, the ESP32-S3's built-in
USB-Serial/JTAG port is enumerated, and its DTR/RTS lines drive EN and the
boot strap. This waits for an unplug and replug, opens the port the instant
its node appears, sends the reset-to-download sequence as fast as the
controller allows, and checks what is on the bus. It keeps trying on every
replug until it succeeds or the time is up. Run with the ESP-IDF python.
"""
import glob
import subprocess
import sys
import time

import serial
from serial.tools import list_ports

WAIT_SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 560
JTAG_PID = 0x1001


def ports():
    return set(glob.glob("/dev/cu.usbmodem*"))


def bus():
    return [(i.device, i.pid) for i in list_ports.comports() if i.device.startswith("/dev/cu.usbmodem")]


def attempt(deadline):
    print("waiting for unplug...", flush=True)
    while ports() and time.time() < deadline:
        time.sleep(0.02)
    if ports():
        return None
    print("unplugged; waiting for replug...", flush=True)
    while not ports() and time.time() < deadline:
        time.sleep(0.001)
    found = ports()
    if not found:
        return None
    port = sorted(found)[0]
    appeared = time.time()
    link = None
    for _ in range(300):
        try:
            link = serial.Serial(port, 115200, timeout=0.2)
            break
        except Exception:
            time.sleep(0.002)
    if not link:
        print("could not open", port)
        return False
    opened = time.time()
    # esptool's USB-Serial/JTAG sequence: RTS drives EN, DTR drives GPIO0.
    link.rts = False; link.dtr = False; time.sleep(0.01)
    link.dtr = True; link.rts = False; time.sleep(0.01)
    link.rts = True; link.dtr = False; link.rts = True; time.sleep(0.01)
    link.dtr = False; link.rts = False
    link.close()
    print(f"opened {int((opened - appeared) * 1000)} ms after the node appeared, "
          f"sequence done at {int((time.time() - appeared) * 1000)} ms", flush=True)
    time.sleep(0.5)
    devices = bus()
    for device, pid in devices:
        print(f"  {device} pid={pid:04x} ({'ROM/JTAG' if pid == JTAG_PID else 'application'})")
    jtag = [d for d, pid in devices if pid == JTAG_PID]
    if not jtag:
        return False
    result = subprocess.run(
        ["esptool.py", "--chip", "esp32s3", "--port", jtag[0], "--before", "no_reset", "--after", "no_reset",
         "--connect-attempts", "3", "flash_id"], capture_output=True, text=True)
    print(result.stdout[-700:], result.stderr[-300:])
    if result.returncode == 0:
        print("PORT", jtag[0])
        return True
    return False


deadline = time.time() + WAIT_SECONDS
while time.time() < deadline:
    outcome = attempt(deadline)
    if outcome is None:
        break
    if outcome:
        sys.exit(0)
    print("missed; replug to try again", flush=True)
print("timed out")
sys.exit(3)
