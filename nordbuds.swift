#!/usr/bin/env swift
//
// NordBuds ANC controller for OnePlus Nord Buds 4 Pro (macOS).
//
// As of mid-2026 the buds no longer expose the BLE control service
// (0000079A-…) on macOS 26 — CoreBluetooth's retrieveConnectedPeripherals
// returns nothing and a broad LE scan never sees them. The control protocol
// is now only reachable over Bluetooth Classic RFCOMM (the vendor "COM" SPP
// service, channel 7 on this hardware). This file talks over that channel.
//
// Must run from a signed .app bundle carrying NSBluetoothAlwaysUsageDescription
// (see build.sh / Info.plist) or macOS TCC silently blocks IOBluetooth.
//

import Foundation
import IOBluetooth

let VERSION = "2.0.0"

// Primary vendor control channel on the Nord Buds 4 Pro. If it ever moves
// (e.g. after re-pairing) we fall back to probing the other SPP channels.
let PRIMARY_CHANNEL: BluetoothRFCOMMChannelID = 7
let FALLBACK_CHANNELS: [BluetoothRFCOMMChannelID] = [7, 6, 5, 1]
let NAME_HINTS = ["Nord Buds", "OnePlus"]

// ANC frames from advnpzn/budsctl oneplus_buds4.yaml. The 7th byte is the
// opcode; the buds ACK with a frame containing `04 84 <opcode>`.
struct AncCommand {
    let name: String
    let payload: [UInt8]
    let opcode: UInt8
}

let COMMANDS: [String: AncCommand] = [
    "on":    AncCommand(name: "ANC ON",       payload: [0xAA,0x0A,0x00,0x00,0x04,0x04,0x48,0x03,0x00,0x01,0x01,0x02], opcode: 0x48),
    "off":   AncCommand(name: "ANC OFF",      payload: [0xAA,0x0A,0x00,0x00,0x04,0x04,0x4A,0x03,0x00,0x01,0x01,0x01], opcode: 0x4A),
    "trans": AncCommand(name: "TRANSPARENCY", payload: [0xAA,0x0A,0x00,0x00,0x04,0x04,0x50,0x03,0x00,0x01,0x01,0x04], opcode: 0x50),
]

final class ChannelDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let opcode: UInt8
    var gotAck = false
    init(opcode: UInt8) { self.opcode = opcode }

    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        let bytes = [UInt8](Data(bytes: data, count: length))
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[RX] \(hex)")
        // ACK frame: … 04 84 <opcode> …
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0x04 && bytes[i + 1] == 0x84 && bytes[i + 2] == opcode {
                gotAck = true
                return
            }
            i += 1
        }
    }

    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {}
}

func findBuds() -> IOBluetoothDevice? {
    guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
    return paired.first { dev in
        let name = dev.name ?? ""
        return NAME_HINTS.contains { name.contains($0) }
    }
}

/// Open `channel`, send the payload, and wait up to `timeout`s for the ACK.
/// Returns true only if the buds acknowledged the opcode.
func trySend(_ cmd: AncCommand, on channel: BluetoothRFCOMMChannelID,
             device: IOBluetoothDevice, timeout: TimeInterval) -> Bool {
    let delegate = ChannelDelegate(opcode: cmd.opcode)
    var chan: IOBluetoothRFCOMMChannel?
    let r = device.openRFCOMMChannelSync(&chan, withChannelID: channel, delegate: delegate)
    guard r == kIOReturnSuccess, let ch = chan else {
        print("[--] channel \(channel) unavailable (\(r))")
        return false
    }

    let write = cmd.payload.withUnsafeBufferPointer {
        ch.writeSync(UnsafeMutablePointer(mutating: $0.baseAddress), length: UInt16(cmd.payload.count))
    }
    let hex = cmd.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("[TX ch\(channel)] \(cmd.name): \(hex) (write=\(write))")

    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline && !delegate.gotAck {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    ch.close()
    return delegate.gotAck
}

func printHelp() {
    print("""
    NordBuds ANC Controller v\(VERSION)  (RFCOMM)

    Usage: nordbuds <command>

    Commands:
      on         Enable ANC (Active Noise Cancellation)
      off        Disable ANC
      trans      Enable Transparency mode
      help       Show this help
    """)
}

func main() -> Int32 {
    let args = CommandLine.arguments
    guard args.count >= 2 else { printHelp(); return 0 }

    let key = args[1].lowercased()
    switch key {
    case "help", "--help", "-h":
        printHelp(); return 0
    case "transparency":
        break // alias handled below
    default:
        break
    }

    let normalized = (key == "transparency") ? "trans" : (key == "anc" ? "on" : key)
    guard let cmd = COMMANDS[normalized] else {
        print("[ERROR] Unknown command: \(key)")
        printHelp()
        return 1
    }

    print("[*] Target: \(cmd.name)")

    guard let device = findBuds() else {
        print("[ERROR] No paired OnePlus / Nord Buds found. Pair them first.")
        return 2
    }
    print("[*] Found: \(device.name ?? "?")  (\(device.addressString ?? "?"))  connected=\(device.isConnected())")

    if !device.isConnected() {
        print("[*] Opening Bluetooth Classic connection…")
        let r = device.openConnection()
        if r != kIOReturnSuccess {
            print("[ERROR] openConnection failed (\(r))")
            return 3
        }
    }

    // Fast path: the known control channel. Fall back to probing the rest
    // (skipping the HFU audio channel) if it has moved.
    if trySend(cmd, on: PRIMARY_CHANNEL, device: device, timeout: 2.0) {
        print("[DONE] \(cmd.name) confirmed")
        return 0
    }
    for ch in FALLBACK_CHANNELS where ch != PRIMARY_CHANNEL {
        if trySend(cmd, on: ch, device: device, timeout: 1.5) {
            print("[DONE] \(cmd.name) confirmed on channel \(ch)")
            return 0
        }
    }

    print("[ERROR] Command sent but no ACK from earbuds. Is Hey Melody / another app holding the channel?")
    return 4
}

exit(main())
