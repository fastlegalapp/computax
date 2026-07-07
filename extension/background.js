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
