const SUPABASE_URL = "https://bpmpkzwnrbmuqnhgdscf.supabase.co";
const statusEl = document.getElementById("status");
const codeEl = document.getElementById("code");
const diagEl = document.getElementById("diag");
const ollamaEl = document.getElementById("ollama");
const strictRefEl = document.getElementById("strictRef");
const ollamaStatusEl = document.getElementById("ollamaStatus");
const aiTierEl = document.getElementById("aiTier");

const PS_AI_TIERS = {
  lite: { ollamaModel: "fleaber-ps-lite", baseModel: "llama3.2:3b" },
  pro: { ollamaModel: "fleaber-ps-pro", baseModel: "qwen2.5:7b" },
};

function resolveOllamaModel(tier, storedModel) {
  const t = String(tier || "auto").toLowerCase();
  if (t === "pro") return PS_AI_TIERS.pro.ollamaModel;
  if (t === "lite") return PS_AI_TIERS.lite.ollamaModel;
  if (storedModel && /fleaber-ps-(lite|pro)/.test(storedModel)) return storedModel;
  return PS_AI_TIERS.lite.ollamaModel;
}

function setStatus(html, cls) {
  statusEl.className = cls || "";
  statusEl.innerHTML = html;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function catalogFromContext(ctx) {
  const items = Array.isArray(ctx?.items) ? ctx.items : [];
  return items.map((it) => ({
    public_slot: it.public_slot ?? it.slot ?? null,
    ref_code: it.ref_code || it.ref || null,
    title: it.title || null,
    is_active: !!(it.is_active || it.active),
  }));
}

function activeRefFromContext(ctx) {
  const items = Array.isArray(ctx?.items) ? ctx.items : [];
  const active = items.find((it) => it.is_active || it.active);
  return active?.ref_code || active?.ref || ctx?.active_ref || null;
}

function renderDiag(cfg, st) {
  if (!cfg?.liveId) {
    diagEl.innerHTML = "Diagnóstico: não emparelhado.";
    return;
  }
  if (!st || !st.updatedAt) {
    diagEl.innerHTML =
      '<span class="warn">Diagnóstico: script ainda não activo nesta página.</span><br>' +
      'Fica no separador do directo Face e clica <b>Activar nesta página Face</b>.';
    return;
  }
  const ageSec = Math.round((Date.now() - st.updatedAt) / 1000);
  const stale = ageSec > 8;
  const cls = stale ? "warn" : "ok";
  const bootOnly = st.boot && !st.scans;
  diagEl.innerHTML =
    `<span class="${cls}">Script: ${st.active ? "ON" : bootOnly ? "a arrancar" : "OFF"} · há ${ageSec}s</span><br>` +
    (st.pageUrl ? `URL: ${escapeHtml(String(st.pageUrl).slice(0, 70))}…<br>` : "") +
    `Scans: ${st.scans || 0} · blocos: ${st.blocksSeen || 0} · parse: ${st.parsed || 0} · enviados: ${st.ingested || 0}<br>` +
    `Fila: ${st.queueDepth || 0}` +
    (st.harnessWaiting ? ' · <span class="warn">à espera de Correr</span>' : "") +
    `<br>IA: usada ${st.llmUsed || 0} · falhou ${st.llmMiss || 0}` +
    (st.lastLlm ? ` · ${escapeHtml(st.lastLlm)}` : "") +
    `<br>Zonas chat: ${st.rootsFound || 0}<br>` +
    (st.lastAction ? `Última acção: ${escapeHtml(st.lastAction)}<br>` : "") +
    (st.lastBlock ? `Último texto: «${escapeHtml(st.lastBlock)}»<br>` : "") +
    (st.lastError ? `<span class="err">Erro: ${escapeHtml(st.lastError)}</span><br>` : "") +
    (stale
      ? '<span class="warn">Sem actividade — clica «Activar nesta página Face»</span>'
      : "");
}

function isFacebookUrl(url) {
  try {
    const u = new URL(url);
    // Face real OU harness local (simulador chat DOM)
    if (/(^|\.)facebook\.com$/i.test(u.hostname)) return true;
    if (
      (u.hostname === "127.0.0.1" || u.hostname === "localhost") &&
      (u.port === "8765" || u.port === "")
    ) {
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

async function findFacebookTab() {
  const tabs = await chrome.tabs.query({});
  const face = tabs.filter((t) => t.url && isFacebookUrl(t.url));
  if (!face.length) return null;
  const active = face.find((t) => t.active);
  if (active) return active;
  face.sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0));
  return face[0];
}

async function injectIntoActiveTab() {
  const tab = await findFacebookTab();
  if (!tab?.id) {
    setStatus(
      "Abre o Facebook Live ou o simulador (http://127.0.0.1:8765/…) noutro separador e volta a clicar.",
      "err",
    );
    return;
  }
  setStatus("A activar script na página Face…");
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content_loader.js"],
    });
    setStatus(
      '<span class="ok">Script injectado.</span> Espera 2s e vê o Diagnóstico.',
      "ok",
    );
    setTimeout(loadState, 800);
    setTimeout(loadState, 2000);
  } catch (e) {
    setStatus(`Falha a injectar: ${e.message || e}`, "err");
  }
}

async function refreshOllamaStatus() {
  const cfg = await new Promise((r) =>
    chrome.storage.local.get(["ollamaEnabled", "ollamaModel", "ollamaTier", "strictRefMode"], r),
  );
  // Default ON (modo testes / regras claras)
  strictRefEl.checked = cfg.strictRefMode !== false;
  ollamaEl.checked = !!cfg.ollamaEnabled;
  aiTierEl.value = cfg.ollamaTier || "auto";
  if (!cfg.ollamaEnabled) {
    ollamaStatusEl.innerHTML = 'IA: <span class="warn">desligada</span>';
    return;
  }
  const model = resolveOllamaModel(cfg.ollamaTier, cfg.ollamaModel);
  chrome.runtime.sendMessage({ type: "ollama_ping" }, (resp) => {
    if (chrome.runtime.lastError || !resp?.ok) {
      const err = resp?.error || chrome.runtime.lastError?.message || "";
      if (/cors_403|403/i.test(String(err))) {
        ollamaStatusEl.innerHTML =
          'IA: <span class="err">bloqueada pelo Ollama (CORS)</span> — corre <code>tool/ps_ai/Setup-OllamaForPs.ps1</code> e reinicia o Ollama';
        return;
      }
      ollamaStatusEl.innerHTML =
        'IA: <span class="err">Ollama offline</span> — abre a app Ollama no PC';
      return;
    }
    const model = resolveOllamaModel(cfg.ollamaTier, cfg.ollamaModel);
    const has = (resp.models || []).some(
      (m) => m === model || m.startsWith(`${model}:`) || model.startsWith(m),
    );
    const tierLabel = (cfg.ollamaTier || "auto").toUpperCase();
    ollamaStatusEl.innerHTML = has
      ? `IA: <span class="ok">${tierLabel} · ${escapeHtml(model)}</span>`
      : `IA: <span class="warn">${tierLabel} · «${escapeHtml(model)}» em falta — corre setup_tiers.ps1</span>`;
  });
}

async function loadState() {
  chrome.storage.local.get(
    ["liveId", "liveTitle", "enabled", "deviceToken", "psExtStats", "ollamaEnabled"],
    (cfg) => {
      if (cfg.liveId && cfg.deviceToken) {
        setStatus(
          `<span class="ok">Ligado: ${escapeHtml(cfg.liveTitle || cfg.liveId)}</span><br>` +
            `Leitura: <b>${cfg.enabled ? "ON" : "OFF"}</b>`,
          "ok",
        );
      } else {
        setStatus("Não emparelhado.", "");
      }
      renderDiag(cfg, cfg.psExtStats);
    },
  );
  await refreshOllamaStatus();
}

document.getElementById("pair").addEventListener("click", async () => {
  const code = codeEl.value.trim();
  if (code.length !== 6) {
    setStatus("Código inválido.", "err");
    return;
  }
  setStatus("A emparelhar…");
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/ps-pairing-claim`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        code,
        device_id: "ps-chrome-ext",
        app_version: "1.2.1",
      }),
    });
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || `HTTP ${res.status}`);
    const ctx = data.live_context || {};
    chrome.storage.local.set(
      {
        liveId: data.live_id,
        deviceToken: data.device_token,
        deviceId: data.device_id || "ps-chrome-ext",
        liveTitle: ctx.live_title || "Live",
        liveCatalog: catalogFromContext(ctx),
        liveActiveRef: activeRefFromContext(ctx),
        enabled: true,
        strictRefMode: true,
        psExtStats: null,
      },
      () => {
        setStatus(
          `<span class="ok">Emparelhado: ${escapeHtml(ctx.live_title || data.live_id)}</span><br>` +
            `<span class="warn">Agora: clica «Activar nesta página Face»</span>`,
          "ok",
        );
        loadState();
      },
    );
  } catch (e) {
    setStatus(String(e.message || e), "err");
  }
});

document.getElementById("inject").addEventListener("click", () => {
  void injectIntoActiveTab();
});

document.getElementById("toggle").addEventListener("click", () => {
  chrome.storage.local.get(["enabled", "liveId"], (cfg) => {
    const next = !cfg.enabled;
    chrome.storage.local.set({ enabled: next }, () => {
      setStatus(
        cfg.liveId
          ? `Leitura: <b>${next ? "ON" : "OFF"}</b>`
          : "Emparelha primeiro.",
        next ? "ok" : "",
      );
      loadState();
    });
  });
});

ollamaEl.addEventListener("change", () => {
  const enabled = !!ollamaEl.checked;
  const tier = aiTierEl.value || "auto";
  const model = resolveOllamaModel(tier, null);
  chrome.storage.local.set(
    {
      ollamaEnabled: enabled,
      ollamaUrl: "http://127.0.0.1:11434",
      ollamaTier: tier,
      ollamaModel: model,
    },
    () => {
      refreshOllamaStatus();
      loadState();
    },
  );
});

strictRefEl?.addEventListener("change", () => {
  chrome.storage.local.set({ strictRefMode: !!strictRefEl.checked }, () => {
    setStatus(
      strictRefEl.checked
        ? '<span class="ok">REF rígido ON</span> — só com palavra REF + código (quero 1 REF AM4 / cancela REF AM4).'
        : '<span class="warn">REF rígido OFF</span> — modo IA/contexto/slots.',
      strictRefEl.checked ? "ok" : "warn",
    );
  });
});

aiTierEl.addEventListener("change", () => {
  const tier = aiTierEl.value || "auto";
  const model = resolveOllamaModel(tier, null);
  chrome.storage.local.set({ ollamaTier: tier, ollamaModel: model }, () => {
    refreshOllamaStatus();
  });
});

document.getElementById("clear").addEventListener("click", () => {
  // Só limpa ops da live — preserva login vendedor e histórico comercial.
  const opsKeys = [
    "liveId",
    "deviceToken",
    "deviceId",
    "liveTitle",
    "liveCatalog",
    "liveActiveRef",
    "sellerHandle",
    "hubLiveUrl",
    "enabled",
    "psExtStats",
    "psStepJournal",
    "psAuthorIdentitySamples",
    "psAuthorIdentityLastProbe",
    "psRunResetToken",
    "liveDurationSnapshotSec",
    "liveDurationSnapshotAt",
  ];
  chrome.storage.local.remove(opsKeys, () => {
    setStatus("Desemparelhado. Sessão vendedor mantida.", "");
    diagEl.textContent = "Diagnóstico: à espera…";
    ollamaEl.checked = false;
    if (strictRefEl) strictRefEl.checked = true;
    ollamaStatusEl.textContent = "IA: …";
  });
});

document.getElementById("probeIdentity").addEventListener("click", async () => {
  const tab = await findFacebookTab();
  if (!tab?.id) {
    setStatus("Abre o Facebook Live (com comentários visíveis) e volta a clicar.", "err");
    return;
  }
  setStatus("A activar script e sondar identidade…");
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content_loader.js"],
    });
  } catch (e) {
    setStatus(`Falha a injectar: ${e.message || e}`, "err");
    return;
  }
  // Espera o import() do content.js + bridge
  let summary = null;
  let lastErr = "";
  for (let i = 0; i < 8; i += 1) {
    await new Promise((r) => setTimeout(r, 400));
    try {
      summary = await chrome.tabs.sendMessage(tab.id, {
        type: "probe_author_identity",
      });
      if (summary?.ok) break;
      lastErr = summary?.error || "sem ok";
      if (summary?.error === "probe_not_ready") continue;
      break;
    } catch (e) {
      lastErr = e.message || String(e);
    }
  }
  if (!summary?.ok) {
    setStatus(
      `Sonda falhou: ${lastErr || "sem resposta"}. ` +
        `Clica «Activar nesta página Face», espera 2s, e «Sondar» outra vez.`,
      "err",
    );
    return;
  }
  try {
    const blob = new Blob([JSON.stringify(summary, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `ps_author_identity_${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  } catch (_) {
    /* ignore */
  }
  setStatus(
    `Sonda OK: <b>${summary.comment_blocks || 0}</b> blocos · ` +
      `href <b>${summary.with_profile_href || 0}</b> · ` +
      `id <b>${summary.with_profile_id || 0}</b> · ` +
      `avatar <b>${summary.with_avatar || 0}</b>. ` +
      `JSON descarregado.`,
    "ok",
  );
});

document.getElementById("exportIdentity").addEventListener("click", () => {
  chrome.storage.local.get(
    ["psAuthorIdentitySamples", "psAuthorIdentityLastProbe", "liveId"],
    (cfg) => {
      const samples = Array.isArray(cfg.psAuthorIdentitySamples)
        ? cfg.psAuthorIdentitySamples
        : [];
      const payload = cfg.psAuthorIdentityLastProbe || {
        type: "ps_author_identity_probe",
        live_id: cfg.liveId || null,
        samples,
        exported_at: new Date().toISOString(),
      };
      if (!samples.length && !(payload.samples && payload.samples.length)) {
        setStatus(
          "Sonda vazia — activa a leitura no Face com comentários, ou clica «Sondar identidade».",
          "warn",
        );
        return;
      }
      const blob = new Blob([JSON.stringify(payload, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `ps_author_identity_${(cfg.liveId || "nolive").slice(0, 8)}_${Date.now()}.json`;
      a.click();
      URL.revokeObjectURL(url);
      setStatus(
        `Sonda exportada: <b>${(payload.samples || samples).length}</b> autores.`,
        "ok",
      );
    },
  );
});

document.getElementById("exportJournal").addEventListener("click", () => {
  chrome.storage.local.get(["psStepJournal", "liveId"], (cfg) => {
    const list = Array.isArray(cfg.psStepJournal) ? cfg.psStepJournal : [];
    if (!list.length) {
      setStatus("Journal vazio — corre comentários com a leitura ON.", "warn");
      return;
    }
    const blob = new Blob([JSON.stringify({ live_id: cfg.liveId || null, steps: list }, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `ps_step_journal_${(cfg.liveId || "nolive").slice(0, 8)}_${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
    setStatus(`Journal exportado: <b>${list.length}</b> passos.`, "ok");
  });
});

document.getElementById("clearJournal").addEventListener("click", () => {
  chrome.storage.local.set({ psStepJournal: [] }, () => {
    setStatus("Journal passos limpo.", "ok");
  });
});

document.getElementById("resetRun").addEventListener("click", () => {
  chrome.storage.local.set(
    {
      psStepJournal: [],
      psExtStats: null,
      psRunResetToken: Date.now(),
    },
    () => {
      setStatus("Estado da corrida limpo. Clica «Correr» para nova ronda.", "ok");
      loadState();
    },
  );
});

document.getElementById("openStudio")?.addEventListener("click", () => {
  chrome.runtime.sendMessage({ type: "open_seller_studio" }, () => {
    void chrome.runtime.lastError;
  });
});

loadState();
setInterval(loadState, 1500);
