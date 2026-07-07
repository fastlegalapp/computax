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
