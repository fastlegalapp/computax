# CompuOffice macOS bridge

A macOS reimplementation of the Windows **CompuOfficeLauncher /
`CompuOffice.ChromeNative.exe`** native-messaging bridge, so the CompuOffice /
CompuTax Chrome extension can talk to a CompuOffice server from a Mac.

> **Read this first — what this does and does not do.**
> This project is only the *bridge* between Chrome and a CompuOffice **server**.
> It does **not** contain, install, or run the CompuOffice/CompuTax application
> itself. The real application is Windows-only and there is no macOS build of it.
>
> This bridge is useful in exactly one situation: your office already runs a
> CompuOffice **server** (on a Windows machine on the LAN, or reachable over the
> network) that serves its UI over HTTP, and you want to reach it from Chrome on
> a Mac. The bridge discovers that server and lets the extension open it. If the
> only copy of CompuOffice is the desktop app on your own Windows PC, running it
> on a Mac still requires a Windows VM (Parallels/UTM) or CrossOver — see
> [docs/running-computax-on-mac.md](docs/running-computax-on-mac.md).

## What it is

On Windows, the CompuOffice Chrome extension (id
`aginpdbdkhdcfgdndhbagboecblnhfgp`) communicates with the local machine through a
[Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
host registered as `compuoffice.native.chrome`. That host discovers the
CompuOffice server on the LAN (UDP broadcast), checks it is up (HTTP), and opens
its web UI.

This repo provides the same native-messaging host for macOS:

| Windows original | This project |
| --- | --- |
| `CompuOffice.ChromeNative.exe` | `host/launcher.py` (+ `host/launcher.sh` wrapper) |
| Registry key `…\NativeMessagingHosts\compuoffice.native.chrome` | `host/compuoffice.native.chrome.json` dropped into each browser's `NativeMessagingHosts` folder |
| `UDPManager.StartSearch` LAN discovery | `discover_server()` in `launcher.py` |
| `IsHttpOk` server health check | `http_ok()` in `launcher.py` |
| `HostDetails` | `host_details()` in `launcher.py` |

## Requirements

- macOS with Google Chrome (also works with Edge, Brave, Chromium, Chrome
  Beta/Canary).
- `python3` — preinstalled via the **Xcode Command Line Tools**. If it is
  missing, run `xcode-select --install` (or install Homebrew python3).
- The CompuOffice Chrome extension installed in the browser.
- A reachable CompuOffice **server** on your network.

## Install

```sh
git clone https://github.com/fastlegalapp/computax.git
cd computax
./install-macos.sh
```

The installer writes the host manifest into every Chromium-family browser it
finds under `~/Library/Application Support`, substituting the absolute path to
`host/launcher.sh`. Fully quit and reopen the browser afterwards.

### Point it at your server

If your CompuOffice server is **not** on `localhost`, or does not answer UDP
discovery, tell the bridge where it is:

```sh
cp host/config.example.json host/config.json
# then edit host/config.json — set server_host and server_port
```

See [host/config.example.json](host/config.example.json) for every option.

## Uninstall

```sh
./uninstall-macos.sh
```

## How the protocol works / adapting to the real extension

The native-messaging wire format and the request dispatch are documented in
[docs/how-it-works.md](docs/how-it-works.md). Because CompuOffice's extension is
closed-source, the exact JSON message *schema* the extension sends may differ
from the generic actions implemented here (`hostdetails`, `discover`, `check`,
`open`). The handler is written so those message names are easy to adjust — see
`handle()` in `host/launcher.py`. If you can capture the messages the real
extension sends (Chrome ▸ extension ▸ *Inspect service worker* ▸ Console), map
them onto the actions in `handle()`.

## Testing without a browser

You can drive the host directly:

```sh
python3 - <<'PY'
import struct, json, subprocess
def frame(o): b=json.dumps(o).encode(); return struct.pack("<I", len(b)) + b
p = subprocess.run(["python3", "host/launcher.py"],
                   input=frame({"action": "discover"}),
                   capture_output=True)
d = p.stdout; (n,) = struct.unpack("<I", d[:4])
print(json.loads(d[4:4+n].decode()))
PY
```

## Legal / scope

This is an independent interoperability bridge for use with software you are
licensed to run. It contains no CompuOffice code and does not redistribute the
CompuOffice application or its Chrome extension. "CompuOffice" and "CompuTax"
are trademarks of their respective owner.
