E="$HOME/CompuOfficeExtension"; mkdir -p "$E"
cat > "$E/manifest.json" <<'MANIFESTEOF'
{
  "manifest_version": 3,
  "name": "CompuOffice Bridge (macOS compat)",
  "version": "1.0.9202.22305",
  "description": "Compatibility bridge so the CompuOffice/CompuTax web app can reach the macOS native helper. Independent interoperability tool; contains no CompuOffice code.",
  "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvlTCGOaEsZZvDF9HKV6d3LaJp3d/fDe57GAgf9G5guWe5GJTIKlRSlVdf3QM0SvKM6YjQ2M/QVEbEAuOrqT6nNyc4cM67hgGE7zDK1XJFhoFa+SlVLwJUPIYquRoj3RO2cNq4BBnCb+xDJHUQPSUZZ+L3mWId+mN8vyL4GUylrdebmVze9DsHT9LEtLmfqiochxCNBQqvavOLi6FbtJWdaXmb/p1IyFDWJ6lpzkutB+aGd2+oT4wkh1v+u/bbfKX6v0wUZajoBuzcRgQntw5ooEsH9q4G2tZ2hauBujvfglEAuazBe/s0ewvPGCMFHCHvZueRmsaYt1gEhupPPZy8wIDAQAB",
  "minimum_chrome_version": "88",
  "background": { "service_worker": "background.js" },
  "content_scripts": [
    {
      "matches": ["*://*.compu.tax/*", "*://localhost/*", "*://127.0.0.1/*"],
      "js": ["content.js"],
      "run_at": "document_start",
      "all_frames": true
    }
  ],
  "externally_connectable": { "matches": ["*://*.compu.tax/*"] },
  "permissions": ["nativeMessaging"],
  "host_permissions": ["*://*.compu.tax/*", "*://localhost/*", "*://127.0.0.1/*"]
}
MANIFESTEOF
cat > "$E/background.js" <<'BGEOF'
// CompuOffice Bridge — background service worker.
//
// Relays messages from the CompuOffice/CompuTax web page (via the content
// script, or directly via externally_connectable) to the macOS native host
// `compuoffice.native.chrome`, and returns the host's reply. Everything is
// logged so we can see exactly what the page asks for and tune the bridge.

const HOST = "compuoffice.native.chrome";

function log() {
  try { console.log.apply(console, ["[CO-BG]"].concat([].slice.call(arguments))); } catch (e) {}
}

function callNative(msg) {
  return new Promise(function (resolve) {
    try {
      chrome.runtime.sendNativeMessage(HOST, msg || {}, function (resp) {
        if (chrome.runtime.lastError) {
          const err = chrome.runtime.lastError.message;
          log("native error:", err, "for", msg);
          resolve({ Status: "Failed", Error: err, ID: msg && (msg.ID || msg.id) });
        } else {
          log("native reply:", resp);
          resolve(resp);
        }
      });
    } catch (e) {
      log("native exception:", String(e));
      resolve({ Status: "Failed", Error: String(e), ID: msg && (msg.ID || msg.id) });
    }
  });
}

// Messages from our content script.
chrome.runtime.onMessage.addListener(function (req, sender, sendResponse) {
  log("onMessage from", sender && sender.url, ":", req);
  const payload = req && req.__native ? req.__native : req;
  callNative(payload).then(sendResponse);
  return true; // async
});

// Messages sent straight from an allowed page (externally_connectable).
if (chrome.runtime.onMessageExternal) {
  chrome.runtime.onMessageExternal.addListener(function (req, sender, sendResponse) {
    log("onMessageExternal from", sender && sender.url, ":", req);
    callNative(req).then(sendResponse);
    return true;
  });
}

// Long-lived port support (some pages connect a port and stream messages).
chrome.runtime.onConnect.addListener(function (port) {
  log("port connected:", port.name);
  port.onMessage.addListener(function (req) {
    log("port message:", req);
    callNative(req).then(function (resp) {
      try { port.postMessage(resp); } catch (e) { log("port post err", String(e)); }
    });
  });
});

log("service worker started; native host =", HOST);
BGEOF
cat > "$E/content.js" <<'CTEOF'
// CompuOffice Bridge — content script.
//
// Injected into CompuOffice/CompuTax pages. It (1) announces the extension's
// presence in several common ways so the page's "is the extension installed?"
// check passes, and (2) bridges window messages from the page to the native
// host via the background worker. Every message the page sends is logged so we
// can learn the real protocol and adjust if needed.

(function () {
  var TAG = "[CO-CS]";
  var VERSION = "1.0.9202.22305";
  function log() {
    try { console.log.apply(console, [TAG].concat([].slice.call(arguments))); } catch (e) {}
  }
  log("injected on", location.href);

  // --- 1. announce presence (several common detection mechanisms) -----------
  try { window.__COMPUOFFICE_EXTENSION__ = VERSION; } catch (e) {}
  try { window.compuofficeExtension = { installed: true, version: VERSION }; } catch (e) {}
  try { document.documentElement.setAttribute("data-compuoffice-ext", VERSION); } catch (e) {}
  function announce() {
    try { window.postMessage({ source: "compuoffice-extension", type: "ready", installed: true, version: VERSION }, "*"); } catch (e) {}
    try { window.dispatchEvent(new CustomEvent("compuoffice-extension-ready", { detail: { version: VERSION } })); } catch (e) {}
  }
  announce();
  document.addEventListener("DOMContentLoaded", announce);

  // --- 2. relay page -> native host -> page ---------------------------------
  window.addEventListener("message", function (ev) {
    if (ev.source !== window) return;
    var d = ev.data;
    if (!d || typeof d !== "object") return;
    if (d.source === "compuoffice-extension") return; // ignore our own replies

    // Log EVERYTHING the page posts, so we can see the real request shape.
    try { log("page message:", JSON.stringify(d).slice(0, 800)); } catch (e) { log("page message (unserializable)"); }

    // Heuristic: a request carries an action somewhere.
    var action = d.action || d.Action || d.cmd || (d.__native && d.__native.action) ||
                 (d.data && d.data.action) || (d.message && d.message.action);
    if (action === undefined) return;

    var corr = d.id || d.ID || d.reqId || d.requestId || d.messageId || null;
    var toSend = d.__native || d.data || d.message || d;

    try {
      chrome.runtime.sendMessage(toSend, function (resp) {
        if (chrome.runtime.lastError) {
          log("relay error:", chrome.runtime.lastError.message);
          window.postMessage({ source: "compuoffice-extension", inReplyTo: corr,
                               error: chrome.runtime.lastError.message }, "*");
          return;
        }
        log("native reply -> page:", JSON.stringify(resp).slice(0, 800));
        // Post the reply back to the page in a few shapes so whatever the page
        // listens for is covered.
        var out = { source: "compuoffice-extension", inReplyTo: corr, response: resp };
        if (resp && typeof resp === "object") { for (var k in resp) { if (!(k in out)) out[k] = resp[k]; } }
        window.postMessage(out, "*");
      });
    } catch (e) {
      log("sendMessage exception:", String(e));
    }
  }, false);

  log("ready; bridging window messages to native host");
})();
CTEOF
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
echo ""
echo "Now: Chrome -> chrome://extensions -> turn on Developer mode ->"
echo "Load unpacked -> choose the folder:  $E"
echo "Then fully quit Chrome (Cmd-Q), reopen, and open your CompuOffice site."

