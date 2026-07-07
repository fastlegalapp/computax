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
