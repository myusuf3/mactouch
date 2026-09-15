#!/usr/bin/env python3
"""Writes docs/protocol-vectors.json, the fixed inputs and expected HMAC that
every implementation of the identify signature must reproduce byte for byte.
Deterministic: the key and nonce are counting byte patterns, not random.

    scripts/gen-vectors.py          # rewrite the file
    scripts/gen-vectors.py --check  # exit 1 if the file is stale
"""
import hashlib
import hmac
import json
import pathlib
import sys

KEY = bytes(range(32))             # 000102...1f
NONCE = bytes(range(0xA0, 0xB0))   # a0a1...af
SLOT = 3

material = f"IDENTIFY|{NONCE.hex()}|{SLOT}"
mac = hmac.new(KEY, material.encode(), hashlib.sha256).hexdigest()

vectors = {
    "device_key": KEY.hex(),
    "nonce": NONCE.hex(),
    "slot": SLOT,
    "material": material,
    "mac": mac,
}
text = json.dumps(vectors, indent=2) + "\n"
path = pathlib.Path(__file__).resolve().parents[1] / "docs" / "protocol-vectors.json"

if "--check" in sys.argv:
    current = path.read_text() if path.exists() else ""
    if current != text:
        print(f"{path} is stale; run scripts/gen-vectors.py", file=sys.stderr)
        sys.exit(1)
    print(f"{path} is current")
else:
    path.write_text(text)
    print(f"wrote {path}")
