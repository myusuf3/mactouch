#!/usr/bin/env python3
"""Send APDUs to the mactouch card through PC/SC, for checking the PIV applet
step by step without pairing anything. Talks to PCSC.framework directly so it
needs no packages and no entitlement.

  scripts/apdu.py select                       # the PIV application
  scripts/apdu.py get 5FC102                   # a data object, 61xx chaining handled
  scripts/apdu.py 00A404000BA000000308000010000100
  printf '00CB3FFF035C017E00\\n' | scripts/apdu.py -   # one APDU per line
"""
import ctypes
import sys

READER = "mactouch smart card"
SELECT_PIV = bytes.fromhex("00A404000BA000000308000010000100")
SCARD_SCOPE_SYSTEM = 2
SCARD_SHARE_SHARED = 2
SCARD_PROTOCOL_T1 = 2
SCARD_LEAVE_CARD = 0

pcsc = ctypes.CDLL("/System/Library/Frameworks/PCSC.framework/PCSC")


class IORequest(ctypes.Structure):
    _fields_ = [("dwProtocol", ctypes.c_uint32), ("cbPciLength", ctypes.c_uint32)]


def check(rc, what):
    if rc != 0:
        sys.exit(f"{what} failed: 0x{rc & 0xFFFFFFFF:08X}")


def connect():
    context = ctypes.c_int32()
    check(pcsc.SCardEstablishContext(SCARD_SCOPE_SYSTEM, None, None, ctypes.byref(context)), "context")
    length = ctypes.c_uint32()
    check(pcsc.SCardListReaders(context, None, None, ctypes.byref(length)), "list readers")
    buffer = ctypes.create_string_buffer(length.value)
    check(pcsc.SCardListReaders(context, None, buffer, ctypes.byref(length)), "list readers")
    readers = [name.decode() for name in buffer.raw.split(b"\0") if name]
    reader = next((name for name in readers if READER in name), None)
    if reader is None:
        sys.exit(f"no reader named {READER}; readers: {readers}")
    card = ctypes.c_int32()
    protocol = ctypes.c_uint32()
    check(pcsc.SCardConnect(context, reader.encode(), SCARD_SHARE_SHARED, SCARD_PROTOCOL_T1,
                             ctypes.byref(card), ctypes.byref(protocol)), "connect")
    return context, card


def transmit(card, apdu):
    pci = IORequest(SCARD_PROTOCOL_T1, ctypes.sizeof(IORequest))
    reply = ctypes.create_string_buffer(4096)
    length = ctypes.c_uint32(len(reply))
    check(pcsc.SCardTransmit(card, ctypes.byref(pci), apdu, len(apdu), None, reply, ctypes.byref(length)), "transmit")
    return reply.raw[:length.value]


def exchange(card, apdu, chain):
    collected = b""
    nxt = apdu
    while True:
        reply = transmit(card, nxt)
        if len(reply) < 2:
            sys.exit("short reply")
        status = int.from_bytes(reply[-2:], "big")
        collected += reply[:-2]
        if chain and status >> 8 == 0x61:
            nxt = bytes([0x00, 0xC0, 0x00, 0x00, status & 0xFF])
        else:
            break
    print(f"> {apdu.hex().upper()}")
    print(f"< {collected.hex().upper() + ' ' if collected else ''}{status:04X}")


def main(args):
    chain = False
    if not args:
        sys.exit(__doc__)
    if args[0] == "select":
        apdus = [SELECT_PIV]
    elif args[0] == "get" and len(args) == 2:
        tag = bytes.fromhex(args[1])
        data = bytes([0x5C, len(tag)]) + tag
        apdus = [SELECT_PIV, bytes([0x00, 0xCB, 0x3F, 0xFF, len(data)]) + data + b"\x00"]
        chain = True
    elif args[0] == "-":
        apdus = [bytes.fromhex(line) for line in sys.stdin.read().split() if line]
    else:
        apdus = [bytes.fromhex("".join(args))]
    context, card = connect()
    try:
        for apdu in apdus:
            exchange(card, apdu, chain)
    finally:
        pcsc.SCardDisconnect(card, SCARD_LEAVE_CARD)
        pcsc.SCardReleaseContext(context)


if __name__ == "__main__":
    main(sys.argv[1:])
