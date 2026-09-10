#!/usr/bin/env python
"""Load mactouch onto a board that is still running tinyTouch, via tinyTouch's
own OTA console commands. Needs a fingerprint touch for AUTH. The image lands
in the second app slot; a power cycle boots it. Run with the ESP-IDF python."""
import base64
import hashlib
import secrets
import sys
import time

import serial

port = sys.argv[1]
image_path = sys.argv[2]
image = open(image_path, "rb").read()
digest = hashlib.sha256(image).hexdigest()
token = secrets.token_hex(16)
CHUNK = 3072

link = serial.Serial(port, 115200, timeout=0.5)
time.sleep(0.3)
link.reset_input_buffer()


def ask(command, timeout, quiet=False):
    link.write((command + "\n").encode()); link.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        raw = link.readline()
        if not raw:
            continue
        line = raw.decode(errors="replace").rstrip()
        if not quiet:
            print("<", line if len(line) < 120 else line[:117] + "...", flush=True)
        if line.startswith(("OK", "ERR", "PONG")):
            return line
    return None


print("> PING"); assert ask("PING", 3)
print("> STATUS"); ask("STATUS", 5)

print("> AUTH (touch the sensor)", flush=True)
auth = None
for attempt in range(14):
    reply = ask("AUTH", 12)
    if reply and reply.startswith("OK AUTH"):
        auth = reply
        break
    time.sleep(0.5)
if not auth:
    print("no fingerprint accepted; giving up"); sys.exit(2)

begin = ask(f"OTA BEGIN {token} {len(image)} {digest}", 10)
if not begin or not begin.startswith("OK OTA BEGIN"):
    print("OTA BEGIN refused"); sys.exit(3)

offset = 0
started = time.time()
while offset < len(image):
    chunk = image[offset:offset + CHUNK]
    reply = ask(f"OTA WRITE {token} {offset} {base64.b64encode(chunk).decode()}", 10, quiet=True)
    if not reply or not reply.startswith("OK OTA WRITE"):
        print(f"write failed at {offset}: {reply}"); sys.exit(4)
    offset += len(chunk)
    if (offset // CHUNK) % 10 == 0 or offset == len(image):
        print(f"  {offset}/{len(image)} bytes", flush=True)
print(f"transfer took {time.time() - started:.1f}s")

commit = ask(f"OTA COMMIT {token}", 30)
if not commit or not commit.startswith("OK OTA STAGED"):
    print("commit refused (signature check or image validation failed)"); sys.exit(5)
print("staged; power-cycle the board to boot mactouch")
