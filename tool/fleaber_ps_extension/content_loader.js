/**
 * Loader clássico (sem type:module no manifest).
 * O Facebook/Chrome por vezes falha em silêncio com content_scripts ES modules.
 *
 * IMPORTANTE: chrome.tabs.sendMessage só chega a ESTE ficheiro (content script).
 * O content.js é import() dinâmico — o listener de mensagens vive aqui e faz bridge.
 */
(function fleaberPsLoader() {
  try {
    chrome.storage.local.set({
      psExtStats: {
        active: false,
        boot: true,
        scans: 0,
        blocksSeen: 0,
        parsed: 0,
        ingested: 0,
        skipped: 0,
        llmUsed: 0,
        llmMiss: 0,
        lastBlock: "",
        lastAction: "boot",
        lastError: "",
        lastLlm: "",
        rootsFound: 0,
        pageUrl: String(location.href || "").slice(0, 160),
        updatedAt: Date.now(),
      },
    });
  } catch (_) {}

  // Evitar cache de módulo antigo após Reload da extensão
  let ver = "dev";
  try {
    ver = chrome.runtime.getManifest().version || "dev";
  } catch (_) {}
  const src = `${chrome.runtime.getURL("content.js")}?v=${encodeURIComponent(ver)}`;

  import(src)
    .then((mod) => {
      if (mod && typeof mod.startFleaberPs === "function") {
        mod.startFleaberPs();
      }
      if (mod && typeof mod.runAuthorIdentityProbeNow === "function") {
        globalThis.__fleaberPsAuthorProbe = mod.runAuthorIdentityProbeNow;
      }
      console.log("[Fleaber PS] content.js OK", ver);
    })
    .catch((err) => {
      console.error("[Fleaber PS] falha a carregar content.js", err);
      try {
        chrome.storage.local.set({
          psExtStats: {
            active: false,
            boot: true,
            lastError: String(err && err.message ? err.message : err),
            pageUrl: String(location.href || "").slice(0, 160),
            updatedAt: Date.now(),
          },
        });
      } catch (_) {}
    });

  // Bridge popup ↔ sonda (Receiving end = este loader)
  try {
    chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
      if (!msg || msg.type !== "probe_author_identity") return false;
      const run = () => {
        const fn = globalThis.__fleaberPsAuthorProbe;
        if (typeof fn !== "function") {
          sendResponse({
            ok: false,
            error: "probe_not_ready",
            hint: "Espera 1s após Activar nesta página Face",
          });
          return;
        }
        try {
          sendResponse(fn());
        } catch (e) {
          sendResponse({ ok: false, error: String(e) });
        }
      };
      // Se o módulo ainda está a carregar, espera um pouco
      if (typeof globalThis.__fleaberPsAuthorProbe === "function") {
        run();
      } else {
        let n = 0;
        const t = setInterval(() => {
          n += 1;
          if (typeof globalThis.__fleaberPsAuthorProbe === "function" || n >= 20) {
            clearInterval(t);
            run();
          }
        }, 100);
      }
      return true;
    });
  } catch (_) {}
})();
