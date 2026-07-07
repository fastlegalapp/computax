#!/usr/bin/env python3
"""
CompuOffice macOS native-messaging host.

This is a macOS reimplementation of the Windows `CompuOffice.ChromeNative.exe`
bridge (part of CompuOfficeLauncher). Chrome/Edge/Brave launch this program and
talk to it over the Native Messaging protocol on stdin/stdout. The browser
extension (id: aginpdbdkhdcfgdndhbagboecblnhfgp) uses it to:

  * discover the CompuOffice server on the local network (UDP broadcast), the
    same job the Windows UDPManager.StartSearch does,
  * health-check that server over HTTP (the Windows `IsHttpOk` check),
  * report host details back to the extension, and
  * open the CompuOffice web UI in the default browser.

Important: this bridge does NOT contain the CompuOffice application. It only
connects the browser to a CompuOffice *server* that is already running and
reachable on the network (typically a Windows machine in the office running the
CompuOffice/CompuTax software, which serves its UI over HTTP). If no such server
is reachable, the bridge will report that no server was found.

The Native Messaging wire format is: a 4-byte little-endian unsigned length,
followed by that many bytes of UTF-8 JSON. See:
https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
"""

import json
import os
import platform
import socket
import struct
import sys
import time
import urllib.error
import urllib.request

# --- configuration -----------------------------------------------------------
# Values mirror the identifiers found in the Windows launcher. They can be
# overridden by a config.json placed next to this file (see config.example.json).

DEFAULT_CONFIG = {
    # UDP ports used to broadcast a discovery probe and listen for the reply.
    # The Windows launcher uses SYSCOPort / ColCoPort / BroadCastPort; the exact
    # integers are read from the CompuOffice install there. Adjust to match your
    # server if discovery does not find it.
    "broadcast_port": 8888,
    "response_port": 8889,
    # The HTTP port the CompuOffice server serves its UI on (COServerPort).
    "server_port": 8080,
    # Optional: a fixed server host/name to use instead of UDP discovery.
    # e.g. "OFFICE-PC" or "192.168.1.50". Empty => try discovery, then localhost.
    "server_host": "",
    # Probe payload broadcast on the LAN; servers that understand it reply with
    # their address. Kept generic because the real wire token is server-defined.
    "discovery_probe": "COMPUOFFICE_DISCOVER",
    # Seconds to wait for discovery replies / HTTP checks.
    "discovery_timeout": 2.0,
    "http_timeout": 3.0,
}


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "config.json")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            user = json.load(fh)
        if isinstance(user, dict):
            cfg.update({k: user[k] for k in user if k in DEFAULT_CONFIG})
    except FileNotFoundError:
        pass
    except (ValueError, OSError):
        # A malformed config should not take the host down; fall back to defaults.
        pass
    return cfg


# --- native messaging framing ------------------------------------------------


def read_message():
    """Read one native message from stdin, or return None on EOF."""
    raw_len = sys.stdin.buffer.read(4)
    if len(raw_len) < 4:
        return None
    (length,) = struct.unpack("<I", raw_len)
    data = sys.stdin.buffer.read(length)
    if len(data) < length:
        return None
    return json.loads(data.decode("utf-8"))


def send_message(obj):
    """Write one native message to stdout."""
    encoded = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


# --- bridge actions ----------------------------------------------------------


def http_ok(url, timeout):
    """Mirror of the Windows IsHttpOk check: GET url, return (ok, status/err)."""
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            code = getattr(resp, "status", resp.getcode())
            return (200 <= code < 400, code)
    except urllib.error.HTTPError as exc:
        return (False, exc.code)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return (False, str(exc))


def discover_server(cfg):
    """
    UDP-broadcast a discovery probe and wait for a reply, mirroring the Windows
    UDPManager.StartSearch. Returns a host string or None.
    """
    probe = cfg["discovery_probe"].encode("utf-8")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(cfg["discovery_timeout"])
        try:
            sock.bind(("", cfg["response_port"]))
        except OSError:
            # If we cannot bind the response port, we can still send and read
            # replies on the ephemeral send socket.
            pass
        sock.sendto(probe, ("255.255.255.255", cfg["broadcast_port"]))
        deadline = time.monotonic() + cfg["discovery_timeout"]
        while time.monotonic() < deadline:
            try:
                data, addr = sock.recvfrom(4096)
            except socket.timeout:
                break
            except OSError:
                break
            # Ignore our own probe echoed back.
            if data == probe:
                continue
            return addr[0]
    finally:
        sock.close()
    return None


def resolve_server(cfg):
    """
    Decide which server host to use: explicit config, then UDP discovery, then
    localhost. Returns (host, discovered_bool).
    """
    if cfg["server_host"]:
        return cfg["server_host"], False
    found = discover_server(cfg)
    if found:
        return found, True
    return "localhost", False


def host_details():
    """Mirror of the Windows HostDetails message."""
    try:
        hostname = socket.gethostname()
    except OSError:
        hostname = ""
    return {
        "hostname": hostname,
        "platform": platform.system(),
        "release": platform.release(),
        "arch": platform.machine(),
        "user": os.environ.get("USER", ""),
        "bridge": "compuoffice-macos",
        "bridgeVersion": "1.0.0",
    }


def open_url(url):
    """Open a URL in the default browser via the macOS `open` command."""
    import subprocess

    try:
        subprocess.Popen(
            ["/usr/bin/open", url],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True, ""
    except OSError as exc:
        return False, str(exc)


def handle(message, cfg):
    """
    Dispatch one request from the extension. The extension's exact schema is
    defined by CompuOffice; we accept an action under any of the common keys and
    always answer with an object carrying the same `action` plus a payload, so
    the extension can correlate request and reply.
    """
    if not isinstance(message, dict):
        return {"ok": False, "error": "expected a JSON object"}

    action = (
        message.get("action")
        or message.get("type")
        or message.get("cmd")
        or message.get("command")
        or ""
    )
    action = str(action).strip().lower()

    if action in ("ping", "hello", "hostdetails", "host_details", ""):
        return {"action": action or "hostdetails", "ok": True, "host": host_details()}

    if action in ("discover", "search", "searchserver", "getserver", "find"):
        host, discovered = resolve_server(cfg)
        url = "http://{0}:{1}".format(host, cfg["server_port"])
        ok, status = http_ok(url, cfg["http_timeout"])
        return {
            "action": action,
            "ok": ok,
            "found": bool(host),
            "discovered": discovered,
            "host": host,
            "port": cfg["server_port"],
            "url": url,
            "reachable": ok,
            "status": status,
        }

    if action in ("httpok", "ping_server", "check", "health"):
        host = message.get("host") or cfg["server_host"] or "localhost"
        port = message.get("port") or cfg["server_port"]
        url = message.get("url") or "http://{0}:{1}".format(host, port)
        ok, status = http_ok(url, cfg["http_timeout"])
        return {"action": action, "ok": ok, "url": url, "reachable": ok, "status": status}

    if action in ("open", "launch", "openurl", "open_url"):
        host = message.get("host") or cfg["server_host"] or "localhost"
        port = message.get("port") or cfg["server_port"]
        url = message.get("url") or "http://{0}:{1}".format(host, port)
        ok, err = open_url(url)
        return {"action": action, "ok": ok, "url": url, "error": err}

    return {"action": action, "ok": False, "error": "unknown action: %s" % action}


def main():
    cfg = load_config()
    while True:
        try:
            message = read_message()
        except (ValueError, OSError):
            break
        if message is None:
            break
        try:
            reply = handle(message, cfg)
        except Exception as exc:  # never let one bad message kill the host
            reply = {"ok": False, "error": "internal error: %s" % exc}
        try:
            send_message(reply)
        except OSError:
            break


if __name__ == "__main__":
    main()
