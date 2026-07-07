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

  // Messages from the page may contain functions (e.g. a payload.callback).
  // Those cannot be structured-cloned through postMessage, so build a
  // JSON-safe copy, dropping any properties that are not cloneable.
  function sanitize(o) {
    try { return JSON.parse(JSON.stringify(o)); } catch (e) {}
    var out = {};
    for (var k in o) {
      if (!Object.prototype.hasOwnProperty.call(o, k)) continue;
      if (typeof o[k] === "function") continue;
      try { JSON.stringify(o[k]); out[k] = o[k]; } catch (e2) {}
    }
    return out;
  }

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
        window.postMessage({ __coBridge: "req", id: id, message: sanitize(message) }, "*");
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
