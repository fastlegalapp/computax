# How the bridge works

## The Native Messaging protocol

Chrome launches the host named by the extension's
`chrome.runtime.connectNative("compuoffice.native.chrome")` call, found via a
manifest in each browser's `NativeMessagingHosts` directory, e.g.:

```
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/compuoffice.native.chrome.json
```

Messages use the standard framing: a 4-byte little-endian length, then that many
bytes of UTF-8 JSON, on stdin/stdout.

`host/launcher.py` is a macOS reimplementation of the Windows
`CompuOffice.ChromeNative.exe` (Professional Softec Pvt. Ltd.), reverse-
engineered from that binary so the CompuTax extension gets identical answers.
`host/launcher.sh` is the wrapper Chrome launches; it locates a working
`python3` (Chrome starts hosts with a minimal `PATH`) and execs `launcher.py`.

## Actions and responses

Requests carry an `action` (and usually `version`, `ID`, and for file ops a file
name + base64 data). Responses copy the exact object shapes the Windows host
emits — the `Status` field is one of `Success`, `Failed`, `already updated`,
`Invalid action`.

| action | purpose | response shape |
| --- | --- | --- |
| `version` | report host version | `{Status, action, Version, ID}` |
| `checkextension` | startup presence check | `{Status, action, ID}` |
| `macaddress` | machine MAC + update flag | `{Status, version, updateRequired, MacAddress, ID}` |
| `selfUpdate` | update check (always "already updated" here) | `{Status, version, updateRequired, MacAddress, ID}` |
| `savefile` | save a file (to the Desktop) | `{Status, action, ID}` |
| `runfile` | save + open a file | `{Status, action, Output, ID}` |
| `printfile` | save + print a file | `{Status, action, ID}` |
| anything else | — | `{Status: "Invalid action", Error, ID}` |

The first four are the **startup handshake**. When they succeed, the CompuTax
web page stops reporting an "extension issue" and loads. `version` reports
`1.0.9202.22305` and `updateRequired` is always `false`, so the page never tries
to trigger the Windows-only self-updater.

The host does **not** open the CompuOffice server connection — the browser loads
your CompuOffice web address (e.g. `fastlegal.compu.tax`) directly. The host only
provides the local-machine features the page cannot do itself: reporting
version/identity and saving/opening/printing files.

## File operations (best-effort on macOS)

The Windows binary's request field names for the file *name* and *data* are not
fully recoverable from the executable, so `savefile`/`runfile`/`printfile` accept
several common spellings (`fileName`/`name`/`filename`, `data`/`fileData`/
`content`/`base64`) and save into `~/Desktop` (the Windows host also uses the
desktop). `runfile` opens with `open`; `printfile` sends to the default printer
with `lp`. If a particular file feature misbehaves, capture the message the
extension sends (Chrome ▸ the extension ▸ *Inspect service worker* ▸ Console) and
adjust the field names in `handle()`.

## Authorized extensions

The manifest authorizes the three CompuTax extension IDs found in the Windows
native-host manifest:

```
ohcokhailmiiebggggbllhllifdldegk
aginpdbdkhdcfgdndhbagboecblnhfgp
pddegllmnldjcaonfinbgaonhfjdbckk
```

Whichever one your Chrome uses, it is allowed to talk to the host.

## Why python3 and a shell wrapper

macOS ships no system Python 2, and Chrome launches native hosts with a
stripped-down environment. The `.sh` wrapper checks the common python3 locations
(`/opt/homebrew`, `/usr/local`, `/usr/bin`, `PATH`, `xcrun --find`) so the host
starts regardless of how python3 was installed.
