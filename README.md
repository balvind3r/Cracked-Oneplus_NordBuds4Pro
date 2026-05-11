# NordBuds Mac — ANC Toggle for OnePlus Nord Buds 4 Pro

Switch ANC / Off / Transparency on **OnePlus Nord Buds 4 Pro** from your Mac,
without the Hey Melody app. Ships as a tiny CLI plus optional
[Raycast](https://www.raycast.com/) script commands so a global hotkey can
flip modes in roughly a second.

> **This is a fork.** All the hard reverse-engineering work was done by
> [@Vedant1521](https://github.com/Vedant1521) in
> [Cracked-Oneplus_buds](https://github.com/Vedant1521/Cracked-Oneplus_buds)
> (Nord Buds 3 Pro). This fork:
>
> - Re-maps the ANC mode bytes for the **Nord Buds 4 Pro** family
>   (`0x01=Off, 0x02=ANC, 0x04=Transparency` — inverted from the 3 Pro).
>   Mapping confirmed from [@advnpzn](https://github.com/advnpzn)'s
>   [budsctl](https://github.com/advnpzn/budsctl) `oneplus_buds4.yaml` plugin.
> - Restricts BLE service/characteristic discovery to the OPO control service
>   only, dropping the FE2C subscription and the blanket notify-on-everything
>   path (≈3 s → ≈0.5 s).
> - Adds a proper `.app` bundle (`NordBuds.app`) with
>   `NSBluetoothAlwaysUsageDescription` so macOS TCC actually grants
>   Bluetooth access instead of `SIGABRT`-ing the process.
> - Adds `nordbuds-cli`, a wrapper that launches the bundle via
>   LaunchServices (so the bundle, not Terminal, is the responsible TCC
>   process) and streams its log back to the terminal.
> - Adds Raycast Script Commands (`silent` mode) for one-hotkey toggling.
> - Adds an RFCOMM fallback (`nordbuds_rfcomm.py`) for variants that don't
>   expose the BLE control service.

---

## Compatibility

### ✅ Confirmed

- **OnePlus Nord Buds 4 Pro** (macOS, Apple Silicon)

### 🔄 Likely to work

Anything in the **OPOv1** family that uses BLE service
`0000079A-D102-11E1-9B23-00025B00A5A5`. Other Nord/Buds models in the same
family (3 Pro, Buds Pro 2, Bullets, several Oppo Enco / Realme Buds) likely
work too, but the mode-byte mapping or auth token may differ — see
*Troubleshooting* below.

### ❌ Won't work out of the box

- Buds that only expose the control protocol over **RFCOMM** (Bluetooth
  Classic SPP) rather than BLE — try the `nordbuds_rfcomm.py` fallback.
- Anything that needs a different REGISTER auth token. The script uses
  Vedant's `B5 50 A0 69`; it's worked on every OPOv1 device tested so far,
  but a btsnoop capture is the only way to confirm for new hardware.

---

## Requirements

- macOS (tested on Apple Silicon, Sonoma+).
- **Xcode Command Line Tools** (for `swiftc` + `codesign`) —
  `xcode-select --install`.
- Buds paired to your Mac under System Settings → Bluetooth.
- *Optional:* [Raycast](https://www.raycast.com/) for hotkey toggles.
- *Optional* (RFCOMM fallback only): `pip install pyobjc-framework-IOBluetooth
  pyobjc-framework-Cocoa`.

---

## Build

```bash
git clone https://github.com/<you>/nordbuds-mac.git
cd nordbuds-mac
./build.sh
```

This produces `NordBuds.app` next to the script (ad-hoc signed, with
`Info.plist` containing the Bluetooth usage description macOS demands).

---

## Usage — CLI

```bash
./nordbuds-cli on      # turn ANC on
./nordbuds-cli off     # turn ANC off
./nordbuds-cli trans   # transparency mode
```

First run: macOS shows a **"NordBuds would like to use Bluetooth"** dialog.
Click **Allow**. Subsequent runs are silent and take ~0.5 s.

If you ever revoke the permission, you can re-grant in
**System Settings → Privacy & Security → Bluetooth**.

---

## Usage — Raycast hotkeys

1. Open **Raycast → Settings → Extensions**, find **Script Commands**.
2. Add `~/path/to/nordbuds-mac/raycast/` as a Script Directory.
3. Run the **Reload Script Directories** Raycast command.
4. Search Raycast for **ANC On / ANC Off / Transparency** and bind hotkeys
   (e.g. ⌃⌥1 / ⌃⌥2 / ⌃⌥3) or aliases.

The scripts run in `silent` mode — no Raycast window pops up, only a small
HUD when the command finishes.

---

## How it works (quick)

1. CoreBluetooth's `retrieveConnectedPeripherals(withServices:)` finds the
   buds by the **OPO** service UUID (`0000079A-…`). This is name-independent
   — renaming the buds in System Settings does not break the script.
2. Discover only the OPO write + notify characteristics.
3. Send three frames back-to-back over the write characteristic:
   `HELLO` → `REGISTER` (with auth token `B5 50 A0 69`) → `SET ANC`.
4. Wait 250 ms for the radio to flush, exit.

Frame format:

```
AA <len> 00 00 <category> <subcmd> <seq> 03 00 01 01 <mode>
```

For Nord Buds 4 Pro:

| Mode          | Byte |
|---------------|------|
| ANC Off       | 0x01 |
| ANC On        | 0x02 |
| Transparency  | 0x04 |

For the Nord Buds 3 Pro mapping and the full protocol writeup, see Vedant's
original [README](https://github.com/Vedant1521/Cracked-Oneplus_buds).

---

## Limitations / things to know

- **Hey Melody must be quit before running.** It holds the control channel
  exclusively; while it's open, your `SET` frames will silently no-op.
- **TCC needs a real `.app` bundle.** Running the bare compiled binary or
  the `.swift` shebang crashes with a privacy violation. Always go through
  `nordbuds-cli` or the bundle's executable launched via `open`.
- **Ad-hoc signing only.** The binary is signed with `codesign -s -` so it
  works on your own machine; it has no Apple Developer ID. macOS may prompt
  the first time about an unidentified developer if you distribute it.
- **No adaptive ANC mode.** The buds support a 4th "adaptive" mode in
  Hey Melody; the opcode byte for it on the 4 Pro hasn't been mapped here.
  If you want it, capture a btsnoop log while toggling Adaptive in
  Hey Melody and diff the SET frame against the other three.
- **No state read-back.** The script fires-and-forgets the mode; it doesn't
  ask the buds "what mode are you in?" before switching. If you want a
  proper three-state toggle, capture the `QUERY` response format and parse it.
- **REGISTER token is shared across devices.** If a future firmware update
  rotates the per-device token, you'll need to re-capture it via btsnoop.
- **Buds 4 Pro only verified.** Other models in the OPOv1 family *should*
  work with possibly different mode bytes / tokens — see Troubleshooting.

---

## Troubleshooting

**`nordbuds quit unexpectedly` / silent abort**
TCC killed the process because the launching app doesn't have Bluetooth
permission attached to a proper Info.plist. Always use `./nordbuds-cli …`
(it goes through the `.app` bundle). Do **not** invoke the bare binary
under `NordBuds.app/Contents/MacOS/` directly.

**`[FOUND]`/`[+]` lines appear but nothing audible happens**
- Hey Melody is open — quit it.
- Mode bytes don't match your variant. Try swapping the mapping in
  `nordbuds.swift` (`sendAncMode(0xXX, …)`), or capture a btsnoop log to
  confirm what your buds expect.
- Auth token mismatch. The SET frame is silently rejected if REGISTER
  didn't authenticate. Capture a btsnoop log of Hey Melody's session and
  patch the bytes after `0x85 0x41 0x05 0x00 0x00` in the REGISTER packet.

**Script never finds the `0000079A` service**
Your buds probably use Bluetooth Classic RFCOMM instead of BLE for control.
Try the fallback:

```bash
pip3 install pyobjc-framework-IOBluetooth pyobjc-framework-Cocoa
./nordbuds_rfcomm.py on
```

Payloads in that script come from budsctl's `oneplus_buds4.yaml`.

---

## File structure

```
nordbuds-mac/
├── nordbuds.swift         CoreBluetooth client (the actual program)
├── Info.plist             Bundle plist with NSBluetoothAlwaysUsageDescription
├── build.sh               Builds + ad-hoc signs NordBuds.app
├── nordbuds-cli           Bash wrapper: open's the .app, tails its log
├── nordbuds_rfcomm.py     RFCOMM fallback (PyObjC + IOBluetooth)
├── raycast/
│   ├── anc-on.sh
│   ├── anc-off.sh
│   └── anc-trans.sh
└── NordBuds.app/          ← built by ./build.sh, gitignored
```

---

## Credits

- **[@Vedant1521](https://github.com/Vedant1521)** — original protocol
  reverse-engineering and Swift implementation for Nord Buds 3 Pro
  ([Cracked-Oneplus_buds](https://github.com/Vedant1521/Cracked-Oneplus_buds)).
- **[@advnpzn](https://github.com/advnpzn)** — protocol opcodes / mode-byte
  mapping for the Buds 4 family ([budsctl](https://github.com/advnpzn/budsctl)).

## License

MIT (inherited from upstream).
