#!/usr/bin/env python3
"""
RFCOMM fallback for OnePlus Nord Buds 4 Pro on macOS.

Use this if `nordbuds.swift` fails (no `0000079A` BLE service found).
Talks to the buds over Bluetooth Classic RFCOMM, channel 15, using the
opcodes from advnpzn/budsctl's `oneplus_buds4.yaml` plugin.

Usage:
    ./nordbuds_rfcomm.py on | off | trans | adaptive

Requirements:
    pip install pyobjc-framework-Cocoa pyobjc-framework-IOBluetooth
"""

from __future__ import annotations

import sys
import time

import objc
from Foundation import NSObject, NSRunLoop, NSDate
from IOBluetooth import IOBluetoothDevice

RFCOMM_CHANNEL = 15

# Exact payloads from budsctl/plugins/oneplus_buds4.yaml
PAYLOADS: dict[str, bytes] = {
    "on":           bytes.fromhex("aa0a00000404480300010102"),
    "off":          bytes.fromhex("aa0a000004044a0300010101"),
    "adaptive":     bytes.fromhex("aa0b000004044c040001010008"),
    "trans":        bytes.fromhex("aa0a00000404500300010104"),
    "transparency": bytes.fromhex("aa0a00000404500300010104"),
}

NAME_HINTS = ("Nord Buds", "OnePlus")


def find_device() -> IOBluetoothDevice | None:
    paired = IOBluetoothDevice.pairedDevices() or []
    for dev in paired:
        name = (dev.name() or "")
        if any(h in name for h in NAME_HINTS):
            return dev
    return None


class _ChanDelegate(NSObject):
    def rfcommChannelData_data_length_(self, ch, data, length):  # noqa: N802
        pass

    def rfcommChannelClosed_(self, ch):  # noqa: N802
        pass

    def rfcommChannelOpenComplete_status_(self, ch, status):  # noqa: N802
        pass


def send(payload: bytes) -> int:
    dev = find_device()
    if dev is None:
        print("[ERROR] No paired OnePlus/Nord Buds found. Pair them first.")
        return 2

    print(f"[OK] Found: {dev.name()}  ({dev.addressString()})")

    if not dev.isConnected():
        print("[*] Connecting (Bluetooth Classic)...")
        err = dev.openConnection()
        if err != 0:
            print(f"[ERROR] openConnection failed: {err}")
            return 3

    delegate = _ChanDelegate.alloc().init()
    chan_ptr = objc.nil
    err, chan = dev.openRFCOMMChannelSync_withChannelID_delegate_(
        chan_ptr, RFCOMM_CHANNEL, delegate
    )
    if err != 0 or chan is None:
        print(f"[ERROR] openRFCOMMChannel({RFCOMM_CHANNEL}) failed: {err}")
        print("        Buds may not expose RFCOMM — try the BLE script instead.")
        return 4

    print(f"[TX] {payload.hex(' ')}")
    err = chan.writeSync_length_(payload, len(payload))
    if err != 0:
        print(f"[ERROR] writeSync failed: {err}")
        chan.closeChannel()
        return 5

    # Drain runloop briefly so the write actually flushes.
    NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(0.5))
    chan.closeChannel()
    print("[DONE]")
    return 0


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in PAYLOADS:
        print("Usage: nordbuds_rfcomm.py {on|off|trans|adaptive}")
        return 1
    return send(PAYLOADS[sys.argv[1]])


if __name__ == "__main__":
    sys.exit(main())
