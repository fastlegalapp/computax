# CompuOffice macOS bridge

A macOS reimplementation of the Windows **`CompuOffice.ChromeNative.exe`**
native-messaging host (by Professional Softec Pvt. Ltd.), so the CompuOffice /
CompuTax Chrome extension works on a Mac instead of failing with an
"extension issue".

> **What this is / isn't.** This is the small local *helper* the CompuTax
> extension needs — the Mac equivalent of the Windows `CompuOfficeExt.exe` /
> `CompuOffice.ChromeNative.exe`. It contains no CompuOffice application code.
> You still reach your data through your CompuOffice web address (e.g.
> `yourfirm.compu.tax`) in the browser; this host just answers the extension's
> local checks and handles saving/printing/opening files.

## How your setup works

CompuTax runs on a machine (your office server), and you use it through Chrome.
The web page loads its own server address directly — but on startup the CompuTax
**extension** asks a **native helper** on your computer for its version, a
presence check, and the machine's MAC address. On Windows that helper is
`CompuOffice.ChromeNative.exe`. On a Mac there is none, so the page reports an
"extension issue" and won't run.

This repo is that helper for macOS. Install it, add the extension, and the page
gets the answers it expects.

| Windows original | This project |
| --- | --- |
| `CompuOffice.ChromeNative.exe` | `host/launcher.py` (+ `host/launcher.sh` wrapper) |
| Registry `…\NativeMessagingHosts\compuoffice.native.chrome` | `host/compuoffice.native.chrome.json` in each browser's `NativeMessagingHosts` folder |
| actions `version` / `checkextension` / `macaddress` / `selfUpdate` | startup handshake in `handle()` — clears the "extension issue" |
| actions `savefile` / `runfile` / `printfile` | local file save / open / print in `handle()` |

The exact protocol is documented in [docs/how-it-works.md](docs/how-it-works.md).

## What you need (three pieces)

1. **This native helper** — install it (below).
2. **The CompuTax Chrome extension** — installed in Chrome on the Mac (IDs:
   `ohcokhailmiiebggggbllhllifdldegk`, `aginpdbdkhdcfgdndhbagboecblnhfgp`, or
   `pddegllmnldjcaonfinbgaonhfjdbckk`; all three are authorized).
3. **`python3`** — preinstalled via the Xcode Command Line Tools; if missing,
   run `xcode-select --install`.

Then open your CompuOffice web address in Chrome as usual.

> **Caveat — DSC / USB signature tokens.** If your workflow signs e-returns with
> a USB DSC token, that hardware is generally Windows-only and this helper does
> not provide it. Data entry and browsing work; token e-signing may not.

## Install

### Easiest: one downloadable file

Download **[`dist/Install-CompuOffice-Bridge.command`](dist/Install-CompuOffice-Bridge.command)**,
then run it once from Terminal. Downloaded `.command` files lose their
executable bit and are quarantined by Gatekeeper, so **double-clicking them
fails with "you do not have appropriate access privileges."** Running them
through `sh` avoids both problems:

1. Open **Terminal** (⌘Space → type `Terminal` → Enter).
2. Type `sh` and a space, drag the downloaded file into the window, press Enter:
   ```sh
   sh ~/Downloads/Install-CompuOffice-Bridge.command
   ```
3. When it finishes, install the CompuTax extension and reopen Chrome.

It installs the helper for every Chromium-family browser on the Mac. There is no
server address to configure — the browser loads your CompuOffice web address
directly.

> Prefer double-clicking? Run this once to make it double-clickable:
> `chmod +x ~/Downloads/Install-CompuOffice-Bridge.command && xattr -d com.apple.quarantine ~/Downloads/Install-CompuOffice-Bridge.command`
> then right-click ▸ Open ▸ Open.

This file is self-contained (the launcher is embedded inside it) and is
regenerated from source with `python3 build-installer.py`.

### Or from a clone

```sh
git clone https://github.com/fastlegalapp/computax.git
cd computax
./install-macos.sh
```

The installer writes the host manifest into every Chromium-family browser it
finds under `~/Library/Application Support`, substituting the absolute path to
`host/launcher.sh`. Fully quit and reopen the browser afterwards.

## Uninstall

```sh
./uninstall-macos.sh
```

## How the protocol works

The wire format and every action/response are documented in
[docs/how-it-works.md](docs/how-it-works.md). The host is a faithful
reimplementation of the Windows `CompuOffice.ChromeNative.exe`, so the responses
match what the extension expects. The startup handshake (`version`,
`checkextension`, `macaddress`, `selfUpdate`) is what clears the "extension
issue"; the file actions (`savefile`, `runfile`, `printfile`) save/open/print to
the Desktop.

## Testing without a browser

You can drive the host directly:

```sh
python3 - <<'PY'
import struct, json, subprocess
def frame(o): b=json.dumps(o).encode(); return struct.pack("<I", len(b)) + b
p = subprocess.run(["python3", "host/launcher.py"],
                   input=frame({"action": "version", "ID": 1}),
                   capture_output=True)
d = p.stdout; (n,) = struct.unpack("<I", d[:4])
print(json.loads(d[4:4+n].decode()))   # -> {"Status":"Success","action":"version",...}
PY
```

## Legal / scope

This is an independent interoperability bridge for use with software you are
licensed to run. It contains no CompuOffice code and does not redistribute the
CompuOffice application or its Chrome extension. "CompuOffice" and "CompuTax"
are trademarks of their respective owner.
