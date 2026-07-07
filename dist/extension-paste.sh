E="$HOME/CompuOfficeExtension"; mkdir -p "$E"
cat > "$E/manifest.json" <<'MANIFESTEOF'
{
  "manifest_version": 3,
  "name": "CompuOffice Bridge (macOS compat)",
  "version": "1.0.9202.22305",
  "description": "Compatibility bridge so the CompuOffice/CompuTax web app can reach the macOS native helper. Independent interoperability tool; contains no CompuOffice code.",
  "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvlTCGOaEsZZvDF9HKV6d3LaJp3d/fDe57GAgf9G5guWe5GJTIKlRSlVdf3QM0SvKM6YjQ2M/QVEbEAuOrqT6nNyc4cM67hgGE7zDK1XJFhoFa+SlVLwJUPIYquRoj3RO2cNq4BBnCb+xDJHUQPSUZZ+L3mWId+mN8vyL4GUylrdebmVze9DsHT9LEtLmfqiochxCNBQqvavOLi6FbtJWdaXmb/p1IyFDWJ6lpzkutB+aGd2+oT4wkh1v+u/bbfKX6v0wUZajoBuzcRgQntw5ooEsH9q4G2tZ2hauBujvfglEAuazBe/s0ewvPGCMFHCHvZueRmsaYt1gEhupPPZy8wIDAQAB",
  "minimum_chrome_version": "111",
  "background": {
    "service_worker": "background.js"
  },
  "content_scripts": [
    {
      "matches": [
        "*://*.compu.tax/*"
      ],
      "js": [
        "inject.js"
      ],
      "run_at": "document_start",
      "all_frames": true,
      "world": "MAIN"
    },
    {
      "matches": [
        "*://*.compu.tax/*"
      ],
      "js": [
        "content.js"
      ],
      "run_at": "document_start",
      "all_frames": true
    }
  ],
  "externally_connectable": {
    "matches": [
      "*://*.compu.tax/*"
    ]
  },
  "permissions": [
    "nativeMessaging"
  ],
  "host_permissions": [
    "*://*.compu.tax/*"
  ]
}
MANIFESTEOF
cat > "$E/background.js" <<'BGEOF'
// CompuOffice Bridge — background service worker.
//
// Relays messages from the content script to the macOS native host
// `compuoffice.native.chrome` and returns its reply.

const HOST = "compuoffice.native.chrome";

function log() {
  try { console.log.apply(console, ["[CO-BG]"].concat([].slice.call(arguments))); } catch (e) {}
}

function callNative(msg) {
  return new Promise(function (resolve) {
    try {
      chrome.runtime.sendNativeMessage(HOST, msg || {}, function (resp) {
        if (chrome.runtime.lastError) {
          log("native error:", chrome.runtime.lastError.message);
          resolve({ Status: "Failed", Error: chrome.runtime.lastError.message });
        } else {
          log("native reply:", resp);
          resolve(resp);
        }
      });
    } catch (e) {
      resolve({ Status: "Failed", Error: String(e) });
    }
  });
}

chrome.runtime.onMessage.addListener(function (req, sender, sendResponse) {
  callNative(req).then(sendResponse);
  return true; // async
});

log("service worker started; native host =", HOST);
BGEOF
cat > "$E/content.js" <<'CTEOF'
// CompuOffice Bridge — isolated-world content script.
//
// Receives intercepted requests from the page-world shim (inject.js) via window
// messages, answers them (talking to the native helper through the background
// worker), and posts the reply back to the shim, which resolves the page's
// original callback.

(function () {
  var VERSION = "1.0.9202.22305";
  function log() {
    try { console.log.apply(console, ["[CO-CS]"].concat([].slice.call(arguments))); } catch (e) {}
  }
  log("content script ready on", location.href);

  function ver(m) { return (m && (m.version || m.ver)) || VERSION; }

  // Ask the native helper something; resolves null on any failure.
  function native(msg) {
    return new Promise(function (resolve) {
      try {
        chrome.runtime.sendMessage(msg, function (resp) {
          if (chrome.runtime.lastError) { log("native err:", chrome.runtime.lastError.message); resolve(null); return; }
          resolve(resp);
        });
      } catch (e) { log("native exception:", String(e)); resolve(null); }
    });
  }

  function handle(msg) {
    var action = String((msg && (msg.action || msg.Action)) || "").toLowerCase();
    log("request action:", action, msg);

    // The startup detection. The page needs {status:"ok", version, updateRequired, macAddress}.
    if (action === "checkextension") {
      return native({ action: "macaddress", version: ver(msg) }).then(function (nat) {
        var mac = (nat && (nat.MacAddress || nat.macAddress)) || "02-00-00-00-00-00";
        var out = { status: "ok", version: ver(msg), updateRequired: false, macAddress: mac };
        log("checkExtension ->", out);
        return out;
      });
    }

    // Everything else: relay to the native helper and adapt the reply so the
    // page's handlers (which read response.response.output) find what they want.
    return native(msg).then(function (nat) {
      if (!nat) return { status: "error", error: "native helper not reachable" };
      var out = { status: "ok", raw: nat };
      var output = (nat.Output !== undefined) ? nat.Output
                 : (nat.output !== undefined) ? nat.output : undefined;
      out.response = { output: output, status: "ok" };
      // also surface common fields at top level
      if (nat.MacAddress || nat.macAddress) out.macAddress = nat.MacAddress || nat.macAddress;
      if (nat.Version) out.version = nat.Version;
      return out;
    });
  }

  window.addEventListener("message", function (ev) {
    if (ev.source !== window) return;
    var d = ev.data;
    if (!d || d.__coBridge !== "req") return;
    handle(d.message || {}).then(function (resp) {
      window.postMessage({ __coBridge: "resp", id: d.id, response: resp }, "*");
    });
  }, false);
})();
CTEOF
cat > "$E/inject.js" <<'INJEOF'
// CompuOffice Bridge — page-world shim (runs in the page's MAIN world).
//
// CompuOffice's page code calls chrome.runtime.sendMessage(<hardcoded CompuTax
// extension id>, {action:"checkExtension", ...}, cb). Our extension has a
// different id, so that message would never reach us. This shim overrides
// chrome.runtime.sendMessage in the page: calls aimed at a CompuTax id are
// intercepted and routed (via window messages) to our isolated content script,
// which talks to the native helper and replies. Calls to any other id fall
// through to the original.

(function () {
  var IDS = {
    ohcokhailmiiebggggbllhllifdldegk: 1,
    aginpdbdkhdcfgdndhbagboecblnhfgp: 1,
    pddegllmnldjcaonfinbgaonhfjdbckk: 1
  };
  var seq = 0;
  var pending = {};

  window.addEventListener("message", function (ev) {
    if (ev.source !== window) return;
    var d = ev.data;
    if (!d || d.__coBridge !== "resp") return;
    var cb = pending[d.id];
    if (cb) { delete pending[d.id]; try { cb(d.response); } catch (e) {} }
  });

  var chrome = window.chrome = window.chrome || {};
  var rt = chrome.runtime = chrome.runtime || {};

  function installShim() {
    var current = rt.sendMessage;
    if (current && current.__coShim) return;              // already ours
    var orig = (typeof current === "function") ? current : null;

    function shim() {
      var args = arguments;
      var extId = args[0];
      if (typeof extId === "string" && IDS[extId]) {
        var message = args[1];
        var cb = null;
        for (var i = 1; i < args.length; i++) {
          if (typeof args[i] === "function") { cb = args[i]; break; }
        }
        var id = ++seq;
        if (cb) pending[id] = cb;
        try { console.log("[CO-INJECT] intercepted sendMessage ->", message && message.action); } catch (e) {}
        window.postMessage({ __coBridge: "req", id: id, message: message }, "*");
        return true;
      }
      if (orig) return orig.apply(rt, args);
      return undefined;
    }
    shim.__coShim = true;
    try {
      Object.defineProperty(rt, "sendMessage", { value: shim, writable: true, configurable: true });
    } catch (e) {
      try { rt.sendMessage = shim; } catch (e2) {}
    }
  }

  installShim();
  // Re-assert in case Chrome (re)defines chrome.runtime after us.
  var tries = 0;
  var iv = setInterval(function () {
    installShim();
    if (++tries >= 40) clearInterval(iv);   // ~10s
  }, 250);

  try { window.__COMPUOFFICE_BRIDGE__ = "1.0.9202.22305"; } catch (e) {}
  try { console.log("[CO-INJECT] sendMessage shim installed"); } catch (e) {}
})();
INJEOF
echo "Extension written to: $E"

# Re-authorize the extension in the native host manifests (adds its ID).
D="$HOME/Library/Application Support/CompuOfficeBridge"
for B in "Google/Chrome" "Google/Chrome Beta" "Microsoft Edge" "BraveSoftware/Brave-Browser" "Chromium"; do
  P="$HOME/Library/Application Support/$B"; [ -d "$P" ] || continue
  mkdir -p "$P/NativeMessagingHosts"
  cat > "$P/NativeMessagingHosts/compuoffice.native.chrome.json" <<JEOF
{"name":"compuoffice.native.chrome","description":"compuoffice native chrome","path":"$D/launcher.sh","type":"stdio","allowed_origins":["chrome-extension://ohcokhailmiiebggggbllhllifdldegk/","chrome-extension://aginpdbdkhdcfgdndhbagboecblnhfgp/","chrome-extension://pddegllmnldjcaonfinbgaonhfjdbckk/","chrome-extension://ikeipdbjlaejlcjldjjhlpdnhlehmdap/"]}
JEOF
  echo "re-authorized: $B"
done
# If a copy was loaded from Downloads, update it too (that is what Chrome runs).
if [ -d "$HOME/Downloads/CompuOfficeExtension" ]; then
  cp -f "$E"/manifest.json "$E"/background.js "$E"/content.js "$E"/inject.js "$HOME/Downloads/CompuOfficeExtension/"
  echo "Updated the Downloads copy too."
fi
echo ""
echo "Now in Chrome: chrome://extensions -> click the RELOAD (circular arrow)"
echo "icon on 'CompuOffice Bridge'. If not loaded yet: Developer mode ON ->"
echo "Load unpacked -> choose:  $E"
echo "Then reload your CompuOffice tab (Cmd-R)."

