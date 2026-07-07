# How the bridge works

## The Native Messaging protocol

Chrome launches the host process named in the extension's
`chrome.runtime.connectNative("compuoffice.native.chrome")` call. It finds the
executable via a manifest file that macOS looks for in each browser's
`NativeMessagingHosts` directory, e.g.:

```
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/compuoffice.native.chrome.json
```

Messages are exchanged on the host's **stdin/stdout** using this framing:

```
[ 4-byte little-endian uint32 length ][ UTF-8 JSON body of that length ]
```

`host/launcher.py` implements both directions (`read_message` / `send_message`).
`host/launcher.sh` is a thin wrapper Chrome actually launches; it locates a
working `python3` (Chrome starts hosts with a minimal `PATH`) and execs
`launcher.py`.

## Request dispatch

`handle()` in `launcher.py` reads an action from any of `action` / `type` /
`cmd` / `command` and answers with a JSON object echoing that action plus a
result. Implemented actions:

| Action (aliases) | What it does | Windows counterpart |
| --- | --- | --- |
| `hostdetails` (`ping`, `hello`, empty) | Return hostname / platform / arch | `HostDetails` |
| `discover` (`search`, `searchserver`, `getserver`) | UDP-broadcast a probe, resolve the server host, then HTTP health-check it | `UDPManager.StartSearch` + `IsHttpOk` |
| `check` (`httpok`, `health`) | HTTP GET a given `url` (or host/port) and report reachability | `IsHttpOk` |
| `open` (`launch`, `openurl`) | Open a `http://host:port` URL in the default browser via `/usr/bin/open` | opening `CompuOffice Online` |

Every reply includes `"ok": true|false`. Unknown actions return
`{"ok": false, "error": "unknown action: …"}`.

## Server discovery

`discover_server()` opens a UDP socket, enables `SO_BROADCAST`, sends the probe
string (`discovery_probe`, default `COMPUOFFICE_DISCOVER`) to
`255.255.255.255:<broadcast_port>`, and waits up to `discovery_timeout` seconds
for any non-echo reply. The replying peer's IP becomes the server host.

`resolve_server()` prefers an explicit `server_host` from `config.json`, then
falls back to discovery, then to `localhost`. The resulting URL is
`http://<host>:<server_port>` — matching the Windows launcher's `http://{0}:{1}`
pattern.

> The exact UDP ports and probe token are defined by the CompuOffice server. The
> Windows launcher reads them from the CompuOffice install (`SYSCOPort`,
> `ColCoPort`, `BroadCastPort`, `COServerPort`). The defaults here are
> placeholders — if discovery does not find your server, set `server_host`
> directly in `config.json`, or adjust the ports/probe to match your server.

## Why python3 and a shell wrapper

macOS no longer ships a system Python 2, and Chrome launches native hosts with a
stripped-down environment. The `.sh` wrapper checks the common python3 locations
(`/opt/homebrew`, `/usr/local`, `/usr/bin`, `PATH`, and `xcrun --find`) so the
host starts regardless of how python3 was installed. If none is found, the
wrapper emits a properly framed native-messaging error so the extension surfaces
a clear message instead of a bare disconnect.
