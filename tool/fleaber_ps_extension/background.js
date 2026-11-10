import { resolveOllamaModel } from "./ps_ai_tiers.js";

const SUPABASE_URL = "https://bpmpkzwnrbmuqnhgdscf.supabase.co";
const OLLAMA_DEFAULT = "http://127.0.0.1:11434";

const SYSTEM_PROMPT = `És um assistente que analisa comentários de Facebook Live em português (Portugal).
Responde APENAS JSON válido com campos:
intent (reserve|cancel|chat|ambiguous),
ref_slug (string|null),
public_slot (int|null),
quantity (int),
confidence (0-1),
needs_review (bool),
reason (string curta).

Regras:
- «afinal ja nao quero Z1» → cancel, ref Z1, quantity 1
- «afinal so quero 5 Z2» → reserve (supersede qty), ref Z2, quantity 5
- «afinal so quero 2» (sem ref) → reserve qty 2, ref = active_ref / último do comprador
- «quero 2 Z1» → reserve, ref Z1, quantity 2
- «tira 2 Z2»: N é DELTA. Se buyer_qty_state.Z2=10 → quantity FINAL 8 (não 2). Sem estado → needs_review true, quantity=delta
- «o mesmo», «tambem», «mais um», «igual ao anterior», «esse» → reserve qty 1, ref = active_ref / último artigo desse comprador (buyer_qty_state / active_ref)
- buyer_qty_state = mapa { REF: qty_actual } desse comprador — USA-O sempre que existir
- chat_recent = mensagens anteriores do chat; chat_recent_meta.total_lines = quantas existem no total; truncated=true se só couber uma parte no pedido (por limite do modelo, não por apagar histórico)
- Para «apenas N» / qty sem ref: (1) buyer_qty_state + histórico do MESMO comprador em chat_recent; (2) se a mensagem responde claramente à linha imediata acima do MESMO comprador (ex. «também», «o mesmo») podes usar a ref dessa linha; (3) se parece conversa social ou ambíguo → intent chat ou needs_review true, NÃO inventes ref
- NUNCA copies ref de outro comprador só porque foi a última mensagem no chat global (ex. Maria «quero o 1» ≠ Ana «apenas 7»)
- «bom dia», «obrigado», «ok», «ainda tem stock?», «quanto custa?» → intent chat, ref_slug null, NÃO reserves
- Nunca inventes refs fora do catalog. Refs fantasma (pt99) → intent cancel/reserve com essa ref, needs_review true; NÃO substituas por outro artigo
- OCR lixo (janao, inquero, inso) — interpreta intenção real
- «C4», «afinal», «so», «Facebook» NUNCA são nomes`;

async function getStorage(keys) {
  return new Promise((resolve) => chrome.storage.local.get(keys, resolve));
}

async function ollamaPing(baseUrl) {
  try {
    const res = await fetch(`${baseUrl.replace(/\/$/, "")}/api/tags`, {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    if (res.status === 403) {
      return {
        ok: false,
        error: "cors_403",
        hint: "OLLAMA_ORIGINS=chrome-extension://*",
      };
    }
    if (!res.ok) return { ok: false, error: `http_${res.status}` };
    const data = await res.json();
    const models = (data.models || []).map((m) => m.name).filter(Boolean);
    return { ok: true, models };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

async function ollamaResolve(comment, catalog, activeRef, cfg, extra = {}) {
  const baseUrl = (cfg.ollamaUrl || OLLAMA_DEFAULT).replace(/\/$/, "");
  let model = cfg.ollamaModel || resolveOllamaModel(cfg.ollamaTier, cfg.ollamaModel) || "fleaber-ps-lite";
  const fallback =
    /pro/i.test(model) ? "qwen2.5:7b" : "llama3.2:3b";
  const user = JSON.stringify({
    comment,
    catalog: catalog || [],
    active_ref: activeRef || null,
    buyer: extra.buyer || null,
    buyer_qty_state: extra.buyer_qty_state || {},
    chat_recent: extra.chat_recent || [],
    chat_recent_meta: extra.chat_recent_meta || {},
  });

  async function chatOnce(modelName) {
    const res = await fetch(`${baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: modelName,
        stream: false,
        format: "json",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user },
        ],
      }),
    });
    if (res.status === 403) {
      return {
        ok: false,
        error: "cors_403",
        model: modelName,
        hint: "OLLAMA_ORIGINS=chrome-extension://*",
      };
    }
    if (!res.ok) return { ok: false, error: `http_${res.status}`, model: modelName };
    const data = await res.json();
    const content = data?.message?.content || "";
    const start = content.indexOf("{");
    const end = content.lastIndexOf("}") + 1;
    if (start < 0 || end <= start) return { ok: false, error: "bad_json", model: modelName };
    const parsed = JSON.parse(content.slice(start, end));
    return { ok: true, result: parsed, model: modelName };
  }

  try {
    let out = await chatOnce(model);
    if (!out.ok && /http_404/i.test(out.error || "") && fallback !== model) {
      out = await chatOnce(fallback);
    }
    return out;
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

async function panelLog(payload) {
  const cfg = await getStorage(["deviceToken"]);
  if (!cfg.deviceToken || !payload?.live_id) return { ok: false, error: "not_configured" };
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/ps-panel-log`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Device-Token": cfg.deviceToken || "",
      },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    return { ok: data.ok === true, error: data.error };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

async function ingestReservation(payload) {
  const cfg = await getStorage(["deviceToken"]);
  const maxAttempts = 4;
  let last = { ok: false, error: "ingest_failed", status: 0 };
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const res = await fetch(
        `${SUPABASE_URL}/functions/v1/ingest-ocr-reservation`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Device-Token": cfg.deviceToken || "",
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(18000),
        },
      );
      let data = {};
      try {
        data = await res.json();
      } catch (_) {
        data = {};
      }
      const errMsg =
        data.error ||
        data.message ||
        data.code ||
        (data.ok ? undefined : `http_${res.status}`);
      last = {
        ok: data.ok === true,
        action: data.action,
        error: errMsg,
        status: res.status,
        ...data,
      };
      if (last.ok) return last;
      // 546 = Edge Function CPU/memória esgotada (Supabase WORKER_RESOURCE_LIMIT)
      const retryable =
        res.status === 546 ||
        res.status === 502 ||
        res.status === 503 ||
        res.status === 504 ||
        res.status === 429 ||
        /WORKER_RESOURCE_LIMIT|WORKER_LIMIT|http_546|timeout|aborted|AbortError/i.test(
          String(errMsg || ""),
        );
      if (!retryable || attempt === maxAttempts) return last;
      await new Promise((r) => setTimeout(r, 700 * attempt * attempt));
    } catch (e) {
      const msg = String(e?.name === "TimeoutError" ? "timeout_18s" : e?.message || e);
      last = { ok: false, error: msg, status: 0 };
      if (attempt === maxAttempts) return last;
      await new Promise((r) => setTimeout(r, 700 * attempt * attempt));
    }
  }
  return last;
}

/** Janela Seller Studio (Etapas 1–3). Popup clássico permanece como fallback. */
let studioWindowId = null;
let classicWindowId = null;

async function openSellerStudio() {
  if (studioWindowId != null) {
    try {
      await chrome.windows.update(studioWindowId, { focused: true });
      return { ok: true, windowId: studioWindowId };
    } catch (_) {
      studioWindowId = null;
    }
  }
  const win = await chrome.windows.create({
    url: chrome.runtime.getURL("studio.html"),
    type: "popup",
    width: 1320,
    height: 860,
    focused: true,
  });
  studioWindowId = win.id ?? null;
  return { ok: true, windowId: studioWindowId };
}

async function openClassicPopup() {
  if (classicWindowId != null) {
    try {
      await chrome.windows.update(classicWindowId, { focused: true });
      return { ok: true, windowId: classicWindowId };
    } catch (_) {
      classicWindowId = null;
    }
  }
  const win = await chrome.windows.create({
    url: chrome.runtime.getURL("popup.html"),
    type: "popup",
    width: 380,
    height: 640,
    focused: true,
  });
  classicWindowId = win.id ?? null;
  return { ok: true, windowId: classicWindowId };
}

chrome.action.onClicked.addListener(() => {
  void openSellerStudio();
});

chrome.windows.onRemoved.addListener((id) => {
  if (id === studioWindowId) studioWindowId = null;
  if (id === classicWindowId) classicWindowId = null;
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  (async () => {
    if (msg.type === "open_seller_studio") {
      sendResponse(await openSellerStudio());
      return;
    }

    if (msg.type === "open_classic_popup") {
      sendResponse(await openClassicPopup());
      return;
    }

    if (msg.type === "panel_log") {
      try {
        sendResponse(await panelLog(msg.payload));
      } catch (e) {
        sendResponse({ ok: false, error: String(e) });
      }
      return;
    }

    if (msg.type === "ingest") {
      try {
        sendResponse(await ingestReservation(msg.payload));
      } catch (e) {
        sendResponse({ ok: false, error: String(e) });
      }
      return;
    }

    if (msg.type === "ollama_ping") {
      const cfg = await getStorage(["ollamaUrl"]);
      sendResponse(await ollamaPing(cfg.ollamaUrl || OLLAMA_DEFAULT));
      return;
    }

    if (msg.type === "ollama_resolve") {
      const cfg = await getStorage([
        "ollamaEnabled",
        "ollamaUrl",
        "ollamaModel",
        "ollamaTier",
        "liveCatalog",
        "liveActiveRef",
      ]);
      if (!cfg.ollamaEnabled) {
        sendResponse({ ok: false, error: "ollama_disabled" });
        return;
      }
      const modelName = resolveOllamaModel(cfg.ollamaTier, cfg.ollamaModel);
      const catalog = msg.catalog || cfg.liveCatalog || [];
      const activeRef = msg.activeRef || cfg.liveActiveRef || null;
      sendResponse(
        await ollamaResolve(msg.comment || "", catalog, activeRef, {
          ...cfg,
          ollamaModel: modelName,
        }, {
          buyer: msg.buyer || null,
          buyer_qty_state: msg.buyer_qty_state || {},
          chat_recent: msg.chat_recent || [],
          chat_recent_meta: msg.chat_recent_meta || {},
        }),
      );
      return;
    }

    sendResponse({ ok: false, error: "unknown_message" });
  })();

  return true;
});
