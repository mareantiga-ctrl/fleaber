import {
  parseCommentLine,
  expandMultiItemParses,
  pseudoId,
  facebookBuyerRefFromProbe,
  resolveExternalBuyerRef,
  lineHash,
  SessionIdentity,
  resolveSlotToRef,
  normalizeOcrLine,
} from "./parser.js";
import {
  ensurePanel,
  setPanelStatus,
  appendPanelEvent,
  clearPanelJournal,
  showQaPrompt,
  setQaBdResult,
  clearQaPrompt,
  selectPanelTab,
} from "./panel.js";

/** Erros de ingest definitivos — não retry / não re-enfileirar no harvest. */
const PERMANENT_INGEST_ERRORS =
  /^(live_ended|item_not_found|live_item_not_available|invalid_token|missing_device_token|unauthorized|forbidden|duplicate|already_|live_not_found|catalog_empty)/i;

function parseOpts(cfg) {
  return {
    strictRef: !!cfg?.strictRefMode,
    // Catálogo emparelhado: em strict, bare «FX1»/«AM4» só conta se estiver aqui.
    catalog: Array.isArray(cfg?.liveCatalog) ? cfg.liveCatalog : [],
  };
}
/** false depois de Reload da extensão — o content script antigo fica órfão nesta página. */
let extRetired = false;

function extAlive() {
  try {
    return !extRetired && !!(chrome?.runtime?.id);
  } catch (_) {
    return false;
  }
}

function retireStaleContentScript(reason) {
  if (extRetired) return;
  extRetired = true;
  try {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  } catch (_) {
    /* ignore */
  }
  try {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
  } catch (_) {
    /* ignore */
  }
  // Não usar console.warn/error — o Chrome lista-os como «Errors» em chrome://extensions
  // depois de Reload, o que assusta sem ser um bug.
  try {
    console.log(
      "[Fleaber PS] script antigo desactivado — faz F5 no separador do directo Face.",
      reason || "",
    );
  } catch (_) {
    /* ignore */
  }
  try {
    setPanelStatus("F5 neste separador Face (Reload da extensão)");
  } catch (_) {
    /* painel pode já não existir */
  }
}

function markSeen(rawLine) {
  if (!rawLine) return false;
  const lh = lineHash(rawLine);
  if (SEEN.has(lh)) return true;
  SEEN.add(lh);
  // Só TTL para chaves sem uid (texto puro) — ver enqueueText
  if (!String(rawLine).includes("\0")) {
    seenTextAt.set(lh, Date.now());
  }
  return false;
}

function goldCandidate(parsed) {
  if (!parsed?.rawLine) return null;
  return {
    comment: parsed.rawLine,
    buyer: parsed.displayName || null,
    intent: parsed.intent || null,
    ref_slug: parsed.refSlug || null,
    public_slot: parsed.publicSlot ?? null,
    quantity: parsed.quantity ?? 1,
  };
}

/** Journal local (chrome.storage) — uma entrada por ingest, mesmo se a BD colapsar supersede. */
async function appendStepJournal(entry) {
  try {
    const cur = await new Promise((r) =>
      chrome.storage.local.get(["psStepJournal"], r),
    );
    const list = Array.isArray(cur.psStepJournal) ? cur.psStepJournal : [];
    list.push({
      t: new Date().toISOString(),
      ...entry,
    });
    // Cap ~2000 passos para não estourar storage
    const trimmed = list.length > 2000 ? list.slice(-2000) : list;
    await new Promise((r) =>
      chrome.storage.local.set({ psStepJournal: trimmed }, r),
    );
  } catch (_) {
    /* ignore */
  }
}

/** Motivos de falha em linguagem humana (para logs CEO + agente). */
function humanFailureReason(err) {
  const e = String(err || "").trim();
  const map = {
    live_ended:
      "A BD marcou o directo como terminado (status ended) — o TCL pode ainda mostrar vídeo. Reactiva a live ou reabre o directo.",
    ingest_failed: "A base de dados recusou o pedido.",
    missing_device_token: "Extensão sem token de emparelhamento.",
    invalid_token: "Token de emparelhamento inválido ou expirado.",
    item_not_found: "Artigo não encontrado no catálogo do directo.",
    "Timed out acquiring connection from connection pool.":
      "Base de dados ocupada (timeout) — tenta de novo em segundos.",
  };
  return map[e] || e || "Erro desconhecido";
}

/** Resumo legível: a IA ajudou, era dispensável, ou falhou? */
function ceoTelemetryExtras({
  parsed,
  ollamaMeta,
  ok,
  error,
  refOut,
  qtyOut,
  action,
}) {
  const raw = (parsed?.rawLine || "").trim();
  const explicitRef = /\b(AM\d|004\/\d+|REF-)/i.test(raw);
  const vagueText =
    !explicitRef &&
    (/apenas\s+\d|s[oó]\s+quero|troca\s+pra|vintage|azul|cal[cç]as|camisola|mesminho|bota\s+o\s+mesmo/i.test(
      raw,
    ) ||
      parsed?.needsReview);
  let iaAjuda = "dispensavel";
  if (vagueText && ollamaMeta?.called && ollamaMeta?.ok) iaAjuda = "ajudou";
  else if (vagueText && ollamaMeta?.called && !ollamaMeta?.ok) iaAjuda = "ia_falhou";
  else if (vagueText && !ollamaMeta?.called) iaAjuda = "precisava_ia_nao_chamada";
  const iaResumo = ollamaMeta?.called
    ? ollamaMeta.ok
      ? `IA respondeu (${ollamaMeta.reason || "ok"})`
      : `IA falhou (${ollamaMeta.error || ollamaMeta.reason || "?"})`
    : "IA não chamada — o texto era claro o suficiente para o parser";
  let resultado = "falhou";
  if (ok) {
    if (action === "cancelled" || parsed?.intent === "cancel") resultado = "cancelado";
    else if (action === "superseded") resultado = "actualizado";
    else resultado = "reserva_registada";
  }
  return {
    ceo_comentario: raw.slice(0, 140),
    ceo_comprador: parsed?.displayName || null,
    ceo_artigo: refOut || parsed?.refSlug || parsed?.publicSlot || "?",
    ceo_quantidade: qtyOut ?? parsed?.quantity ?? null,
    ceo_ia_ajudou: iaAjuda,
    ceo_ia_resumo: iaResumo,
    ceo_resultado: resultado,
    ceo_motivo_falha: ok ? null : humanFailureReason(error),
  };
}

/** Telemetria para o harness local — o agente lê tool/ps_ai/runs/ sozinho. */
function postTelemetry(entry) {
  try {
    void fetch("http://127.0.0.1:8765/ps_ai/runs/telemetry", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(entry),
    }).catch(() => {});
  } catch (_) {
    /* ignore */
  }
}

function logPanelEvent({ kind, message, detail, meta, parsed }) {
  appendPanelEvent({ kind, message, detail });
  const gc = parsed ? goldCandidate(parsed) : null;
  const metaOut =
    gc && (!meta || !meta.gold_candidate)
      ? { ...(meta || {}), gold_candidate: gc }
      : meta || null;
  void getConfig().then((cfg) => {
    if (!cfg.liveId || !cfg.deviceToken) return;
    void sendMessage("panel_log", {
      payload: {
        live_id: cfg.liveId,
        device_id: cfg.deviceId || "ps-chrome-ext",
        event_kind: kind || "info",
        message: message || "",
        detail: detail || null,
        meta: metaOut,
      },
    });
  });
}

const SEEN = new Set();
const QUEUED = new Set();
const workQueue = [];
let workersBusy = 0;
/**
 * 1 worker = ingest à BD em série (ordem do chat).
 * 2+ em paralelo é mais rápido mas perigoso: cancel/supersede da msg N
 * pode correr ao mesmo tempo que a reserva N+1 e «roubar» linhas
 * (sintoma Lab: a meio da bateria fica só 1 comprador / refs a desaparecer).
 * Parse/IA pode voltar a paralelizar depois com fila de commit ordenada.
 */
const MAX_WORKERS = 1;
const identity = new SessionIdentity();
const lastQty = {};
let seq = 0;
let timer = null;
let observer = null;
let lastRootKey = "";
let scanInFlight = false;
let lastHarnessRunId = null;
let drainUntil = 0;

/** Chat completo da corrida (OCR/DOM) — só limpa em resetRunMemory / nova bateria. */
const chatTranscript = [];
let persistTranscriptTimer = null;

function persistChatTranscriptNow() {
  const lines = chatTranscript.map((e, i) => ({
    n: i + 1,
    t: e.t,
    uid: e.uid || "",
    buyer: e.buyer,
    text: e.text,
  }));
  chrome.storage.local.set({
    psChatTranscript: lines,
    psChatTranscriptCount: lines.length,
    psChatTranscriptUpdatedAt: Date.now(),
  });
  try {
    void getConfig().then((cfg) => {
      void fetch("http://127.0.0.1:8765/ps_ai/runs/chat_transcript", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          live_id: cfg.liveId || null,
          count: lines.length,
          lines,
          saved_at: new Date().toISOString(),
        }),
      }).catch(() => {});
    });
  } catch (_) {
    /* ignore */
  }
}

function schedulePersistChatTranscript() {
  if (persistTranscriptTimer) clearTimeout(persistTranscriptTimer);
  persistTranscriptTimer = setTimeout(() => {
    persistTranscriptTimer = null;
    persistChatTranscriptNow();
  }, 1500);
}

/** Chat Trace (Modo Técnico) — diagnóstico FB → Chat. Cap 80. */
const chatTraceLog = [];
let persistTraceTimer = null;

function pushChatTrace(entry) {
  chatTraceLog.push({
    t: Date.now(),
    ...entry,
  });
  while (chatTraceLog.length > 80) chatTraceLog.shift();
  if (persistTraceTimer) clearTimeout(persistTraceTimer);
  persistTraceTimer = setTimeout(() => {
    persistTraceTimer = null;
    try {
      chrome.storage.local.set({
        psChatTrace: chatTraceLog.slice(-80),
        psChatTraceUpdatedAt: Date.now(),
      });
    } catch (_) {
      /* ignore */
    }
  }, 400);
}

function appendChatTranscript(text, uid = "", authorHint = null) {
  const line = (text || "").trim();
  // Pipeline: NÃO filtrar aqui por «dirty OCR» — isso é só na camada DISPLAY do Studio.
  if (!line || isNoise(line)) {
    pushChatTrace({
      stage: "DROPPED",
      reason: !line ? "empty" : "isNoise",
      text: line.slice(0, 120),
      uid: uid || "",
    });
    return;
  }
  const h = lineHash(uid ? `${uid}\0${line}` : line);
  if (chatTranscript.some((e) => e.h === h)) {
    pushChatTrace({
      stage: "DROPPED",
      reason: "dedupe_hash",
      text: line.slice(0, 120),
      uid: uid || "",
    });
    return;
  }
  if (uid && chatTranscript.some((e) => e.uid === uid && e.text === line)) {
    pushChatTrace({
      stage: "DROPPED",
      reason: "dedupe_uid_text",
      text: line.slice(0, 120),
      uid,
    });
    return;
  }
  const p = parseCommentLine(line);
  let buyer = p?.displayName || null;
  if (!buyer && authorHint) buyer = String(authorHint).trim() || null;
  if (!buyer) {
    try {
      const split = splitNameBodyForChat(line);
      if (split?.name && split?.body && split.body !== line) buyer = split.name;
    } catch (_) {
      /* ignore */
    }
  }
  chatTranscript.push({
    t: Date.now(),
    h,
    uid: uid || "",
    buyer,
    text: line,
  });
  schedulePersistChatTranscript();
  pushChatTrace({
    stage: "TRANSCRIPT",
    text: line.slice(0, 120),
    buyer: buyer || "",
    uid: uid || "",
  });
}

/**
 * Contexto para a IA: preferir linhas do MESMO comprador (evita roubar ref).
 */
function chatPackForOllama(currentText, parsed) {
  const curH = lineHash((currentText || "").trim());
  const buyerKey = (parsed?.displayName || "")
    .trim()
    .toLowerCase();
  const prior = chatTranscript.filter((e) => e.h !== curH);
  const sameBuyer = buyerKey
    ? prior.filter(
        (e) => (e.buyer || "").trim().toLowerCase() === buyerKey,
      )
    : [];
  // Ambíguo: primeiro histórico deste comprador; se vazio, só últimas 8 linhas globais
  const ambiguous =
    !parsed?.refSlug ||
    parsed?.publicSlot != null ||
    !!parsed?.needsReview ||
    parsed?.reason === "qty_only_supersede" ||
    parsed?.reason === "continuity_last_ref" ||
    parsed?.reason === "context_echo" ||
    parsed?.reason === "title_guess";
  let pool = sameBuyer.length ? sameBuyer : prior.slice(-8);
  if (!ambiguous && sameBuyer.length) pool = sameBuyer.slice(-40);
  if (ambiguous && sameBuyer.length) pool = sameBuyer.slice(-80);
  if (ambiguous && !sameBuyer.length) pool = prior.slice(-8);
  const total = prior.length;
  const lines = pool.map((e, i) => ({
    n: i + 1,
    buyer: e.buyer,
    text: e.text.slice(0, 220),
  }));
  return {
    lines,
    total_lines: total,
    sent_lines: lines.length,
    truncated: sameBuyer.length < total,
    same_buyer_only: sameBuyer.length > 0,
  };
}

const stats = {
  active: false,
  scans: 0,
  blocksSeen: 0,
  parsed: 0,
  ingested: 0,
  skipped: 0,
  llmUsed: 0,
  llmMiss: 0,
  queueDepth: 0,
  lastBlock: "",
  lastAction: "",
  lastError: "",
  lastLlm: "",
  rootsFound: 0,
  pageUrl: "",
  harnessMode: false,
  harnessWaiting: false,
};

function reportStats() {
  stats.pageUrl = location.href.slice(0, 120);
  const payload = { ...stats, updatedAt: Date.now(), workersBusy };
  chrome.storage.local.set({ psExtStats: payload });
  const run = getHarnessRunState();
  if (run.isHarness && run.runId) {
    try {
      void fetch("http://127.0.0.1:8765/ps_ai/runs/progress", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          run_id: run.runId,
          ingested: stats.ingested,
          queue_depth: stats.queueDepth || 0,
          workers_busy: workersBusy,
          parsed: stats.parsed,
          skipped: stats.skipped,
          blocks_seen: stats.blocksSeen,
          active: stats.active,
          harness_reason: run.reason,
        }),
      }).catch(() => {});
    } catch (_) {
      /* ignore */
    }
  }
}

function resetRunMemory(reason = "reset") {
  SEEN.clear();
  seenTextAt.clear();
  QUEUED.clear();
  workQueue.length = 0;
  workersBusy = 0;
  stats.queueDepth = 0;
  seq = 0;
  identity.lastValidName = null;
  identity.byRef = {};
  identity.byBuyer = {};
  identity.lastRef = null;
  Object.keys(lastQty).forEach((k) => delete lastQty[k]);
  chatTranscript.length = 0;
  if (persistTranscriptTimer) {
    clearTimeout(persistTranscriptTimer);
    persistTranscriptTimer = null;
  }
  chrome.storage.local.remove([
    "psChatTranscript",
    "psChatTranscriptCount",
    "psChatTranscriptUpdatedAt",
  ]);
  stats.scans = 0;
  stats.blocksSeen = 0;
  stats.parsed = 0;
  stats.ingested = 0;
  stats.skipped = 0;
  stats.llmUsed = 0;
  stats.llmMiss = 0;
  stats.lastBlock = "";
  stats.lastAction = reason;
  stats.lastError = "";
  stats.lastLlm = "";
  drainUntil = 0;
}

function getHarnessRunState() {
  const host = location.hostname;
  const isHarness =
    (host === "127.0.0.1" || host === "localhost") &&
    (location.port === "8765" || location.port === "");
  if (!isHarness) return { isHarness: false, active: true, runId: null, reason: "" };
  const el = document.getElementById("psHarnessRunState");
  const active = (el?.dataset.active || document.body?.dataset?.psRunActive || "0") === "1";
  const runId = el?.dataset.runId || document.body?.dataset?.psRunId || null;
  const reason = el?.dataset.reason || "";
  return { isHarness: true, active, runId, reason };
}

function statusLine() {
  const run = getHarnessRunState();
  const wait = run.isHarness && !run.active && !(workQueue.length || workersBusy);
  const draining = run.isHarness && !run.active && (workQueue.length || workersBusy || Date.now() < drainUntil);
  let mode = "";
  if (run.isHarness) {
    if (wait) mode = " · à espera de Correr";
    else if (draining) mode = ` · a fechar fila (${workQueue.length})`;
    else if (run.active) mode = " · bateria ON";
  }
  const pending = (stats.queueDepth || 0) + workersBusy;
  const total = stats.ingested + pending;
  return (
    `Leitura ${stats.active ? "ON" : "OFF"} · ${stats.ingested}/${total || stats.ingested}` +
    ` (fila ${stats.queueDepth || 0}) · IA ${stats.llmUsed}/${stats.llmMiss}` +
    `${ollamaUnreachable ? " OFFLINE" : ""}${mode}`
  );
}

function findChatRoots() {
  const roots = new Set();
  const selectors = [
    '[data-testid="UFI2CommentsList/root"]',
    '[data-testid*="comment-stream" i]',
    '[data-testid*="Comment" i]',
    '[aria-label*="Coment" i]',
    '[aria-label*="Comment" i]',
    'div[role="complementary"]',
    'div[role="feed"]',
    '[data-pagelet*="Chat"]',
    '[data-pagelet*="Comment"]',
  ];
  for (const sel of selectors) {
    try {
      document.querySelectorAll(sel).forEach((el) => {
        const root =
          el.closest('[role="complementary"]') ||
          el.closest('[role="feed"]') ||
          el.closest('[role="main"]') ||
          el;
        if (root) roots.add(root);
      });
    } catch (_) {
      /* selector inválido em versões antigas */
    }
  }
  if (roots.size === 0) {
    document.querySelectorAll('div[role="main"]').forEach((el) => roots.add(el));
  }
  if (roots.size === 0) roots.add(document.body);
  return [...roots];
}

function stripFbUi(text) {
  return text
    .replace(/\s*·\s*\d+\s*(m|min|h|horas?)\s*/gi, " ")
    .replace(/\b(\d+)\s*min(?=[a-zà-ú])/gi, "$1 ")
    .replace(/\s*a\s+publicar\.{0,3}\s*$/i, "")
    .replace(/\s*·\s*\d+\s*(m|min|h|horas?)\s*$/i, "")
    .replace(
      /\b(?:Liked by|Loved by|Reacted by|Gostou|Reagiu)\b.*?(?=\s*(?:quero|queria|kero|ker|qero|reservo|reserva|manda|mandar|dame|fico|fica|pega|meve|txiga|o\s+mesmo|a\s+mesma|so\s+|só\s+|ja\s+|já\s+|afinal|tira|cancela|retira|[A-Za-z]{1,4}\d)|$)/gi,
      " ",
    )
    .replace(/\bView\s+\d+\s+more\s+replies?\s+/gi, " ")
    .replace(/\bView\s+\d+\s+replies?\s+/gi, " ")
    .replace(/\bSee\s+translation\b/gi, " ")
    .replace(/\bVer\s+tradu[cç][aã]o\b/gi, " ")
    .replace(/\bTranslate\s+to\s+\w+\b/gi, " ")
    .replace(/\bWrite\s+a\s+comment[.…]*\b/gi, " ")
    .replace(/\bEscreve(?:r)?\s+um\s+coment[aá]rio[.…]*\b/gi, " ")
    .replace(/\bPinned\s+(?:comment|by\s+[^\s]+)\b/gi, " ")
    .replace(/\bComent[aá]rio\s+fixado\b/gi, " ")
    .replace(/\bMost\s+relevant\b/gi, " ")
    .replace(/\bAll\s+comments\b/gi, " ")
    .replace(/\bTop\s+fan\b/gi, " ")
    .replace(/\b(?:Just\s+now|Agora\s+mesmo)\b/gi, " ")
    .replace(/\b\d+\s*(?:likes?|gostos?|reactions?)\b/gi, " ")
    .replace(/\bShared\s+(?:a\s+)?(?:post|live|video)\b/gi, " ")
    .replace(
      /\s+\bin\s+(?=(?:liked\b|view\b|loved\b|reacted\b|o\s+mesmo\b|a\s+mesma\b|so\s+|só\s+|quero\b|manda\b|dame\b|ja\s+|já\s+|afinal\b|tira\b))/gi,
      " ",
    )
    .replace(/\s*(Responder|Reply|Gosto|Like|Partilhar|Share|Seguir|Follow)\s*$/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Sonda identidade Face (observação só — NÃO altera reservas/claim).
 * Preferir o link do **autor do comentário** (texto = nome + profile.php?id=…&comment_id=),
 * nunca o primeiro href de perfil no artigo (pode ser página/live/outro).
 */
function parseFbProfileFromHref(href) {
  const h = String(href || "").trim();
  if (!h) return null;
  // Permalink de tempo no vídeo da Page (…/videos/ID/?comment_id=) — NÃO é autor
  if (/\/videos\/\d+/i.test(h) && !/profile\.php\?id=/i.test(h)) {
    return null;
  }
  if (/\/(watch|reel|videos|posts|photo|sharer|login|story|search)\b/i.test(h) && !/[?&]comment_id=/i.test(h)) {
    return null;
  }
  const idM =
    h.match(/[?&]id=(\d{5,})/) ||
    h.match(/\/profile\.php\?id=(\d{5,})/) ||
    h.match(/\/people\/[^/]+\/(\d{5,})/);
  let vanity = null;
  if (!idM) {
    const pathM = h.match(/facebook\.com\/([A-Za-z0-9._-]{3,})(?:\/|\?|$)/i);
    const v = pathM ? pathM[1] : null;
    if (
      v &&
      !/^(profile\.php|people|watch|reel|videos|photo|photos|pages|groups|events|login|sharer)$/i.test(v)
    ) {
      vanity = v;
    }
  }
  if (!idM && !vanity) return null;
  return {
    id: idM ? idM[1] : null,
    vanity,
    hasCommentId: /[?&]comment_id=/i.test(h),
  };
}

function livePageOwnerIdFromLocation() {
  try {
    const href = String(location.href || "");
    const m =
      href.match(/facebook\.com\/(?:profile\.php\?id=)?(\d{10,})(?:\/|$|\?)/) ||
      href.match(/\/(\d{10,})\/videos\//);
    return m ? m[1] : null;
  } catch (_) {
    return null;
  }
}

/** Decodifica comment_id do href (base64 «comment:video_comment» ou cru). */
function decodeFbCommentKey(href) {
  const m = String(href || "").match(/[?&]comment_id=([^&]+)/i);
  if (!m) return null;
  let raw = m[1];
  try {
    raw = decodeURIComponent(raw);
  } catch (_) {
    /* keep */
  }
  try {
    const dec = atob(raw.replace(/-/g, "+").replace(/_/g, "/"));
    if (/^comment:/i.test(dec)) return dec;
  } catch (_) {
    /* not b64 */
  }
  return raw;
}

/**
 * Varrimento profundo: cada comentário = href profile.php?id=X&comment_id=Y
 * (o mesmo contrato do clique no nome no Face — ground truth A/B Monteiro).
 * Não depende só de role=article (alguns nós ficavam de fora / ID colapsado).
 */
function deepScanAuthorIdentities(root) {
  const scope = root || document;
  const pageOwner = livePageOwnerIdFromLocation();
  /** @type {Map<string, object>} */
  const byComment = new Map();

  let links;
  try {
    links = scope.querySelectorAll('a[href*="comment_id="]');
  } catch (_) {
    links = [];
  }

  for (const a of links) {
    const href = (a.getAttribute("href") || "").trim();
    if (!href) continue;
    const parsed = parseFbProfileFromHref(href);
    if (!parsed || (!parsed.id && !parsed.vanity)) continue;
    if (!parsed.hasCommentId) continue;
    if (pageOwner && parsed.id && parsed.id === pageOwner) continue;

    const ckey = decodeFbCommentKey(href);
    if (!ckey) continue;

    const text = (a.textContent || "").trim().slice(0, 80);
    const name = cleanAuthorDisplayHint(text);
    let score = 20;
    if (name && name.length >= 2) score += 50;
    if (a.querySelector("img, image")) score += 30;
    if (parsed.id) score += 15;

    const img =
      a.querySelector('img[src*="scontent"], img, image') ||
      a.parentElement?.querySelector?.('img[src*="scontent"]');
    const probe = {
      name_hint: name || null,
      profile_href: href.slice(0, 400),
      profile_id_guess: parsed.id || parsed.vanity || null,
      avatar_src: img
        ? (img.getAttribute("src") || img.getAttribute("xlink:href") || "").slice(0, 500)
        : null,
      avatar_alt: img ? (img.getAttribute("alt") || "").slice(0, 120) : null,
      data_attrs: { comment_key: ckey },
      link_samples: [{ href: href.slice(0, 240), text }],
      captured_at: new Date().toISOString(),
      _score: score,
      _el: a.closest('[role="article"]') || a.closest("div") || a,
    };

    const prev = byComment.get(ckey);
    if (!prev || score > (prev._score || 0)) {
      byComment.set(ckey, probe);
    }
  }

  return [...byComment.values()];
}

function probeAuthorIdentity(art, nameHint) {
  const out = {
    name_hint: nameHint || null,
    profile_href: null,
    profile_id_guess: null,
    avatar_src: null,
    avatar_alt: null,
    data_attrs: {},
    link_samples: [],
    captured_at: new Date().toISOString(),
  };
  try {
    // 1) Preferir links com comment_id DENTRO deste nó (contrato do clique Face)
    const deepHere = deepScanAuthorIdentities(art);
    if (deepHere.length === 1) {
      const d = deepHere[0];
      out.name_hint = d.name_hint || out.name_hint;
      out.profile_href = d.profile_href;
      out.profile_id_guess = d.profile_id_guess;
      out.avatar_src = d.avatar_src;
      out.avatar_alt = d.avatar_alt;
      out.link_samples = d.link_samples || [];
      out.data_attrs = d.data_attrs || {};
      return out;
    }
    if (deepHere.length > 1) {
      // Homónimos no mesmo subtree: escolher pelo nome do hint
      const cleanName = cleanAuthorDisplayHint(nameHint || "").toLowerCase();
      const named = deepHere.find(
        (d) =>
          cleanName &&
          d.name_hint &&
          d.name_hint.toLowerCase() === cleanName,
      );
      const pick = named || deepHere.sort((a, b) => (b._score || 0) - (a._score || 0))[0];
      out.name_hint = pick.name_hint || out.name_hint;
      out.profile_href = pick.profile_href;
      out.profile_id_guess = pick.profile_id_guess;
      out.avatar_src = pick.avatar_src;
      out.avatar_alt = pick.avatar_alt;
      out.link_samples = pick.link_samples || [];
      out.data_attrs = pick.data_attrs || {};
      return out;
    }

    // 2) Fallback antigo (scoring) se não houver comment_id no nó
    const cleanName = cleanAuthorDisplayHint(nameHint || "");
    const nameLower = cleanName.toLowerCase();
    const pageOwner = livePageOwnerIdFromLocation();
    const links = Array.from(art.querySelectorAll("a[href]")).slice(0, 24);
    const candidates = [];

    for (const a of links) {
      const href = (a.getAttribute("href") || "").trim();
      if (!href) continue;
      const text = (a.textContent || "").trim().slice(0, 80);
      out.link_samples.push({ href: href.slice(0, 240), text });
      const parsed = parseFbProfileFromHref(href);
      if (!parsed) continue;
      if (pageOwner && parsed.id && parsed.id === pageOwner) continue;

      let score = 0;
      if (parsed.id) score += 15;
      if (parsed.vanity) score += 8;
      if (parsed.hasCommentId) score += 55;
      if (nameLower && text) {
        const t = text.toLowerCase();
        if (t === nameLower) score += 120;
        else if (nameLower.startsWith(t) && t.length >= 4) score += 60;
        else if (t.startsWith(nameLower.split(/\s+/)[0] || "___") && t.length >= 4) {
          score += 35;
        }
      }
      if (a.querySelector("img, image")) score += 40;
      if (text && !/^\d+\s*(min|h|utos)/i.test(text) && text.length < 80) score += 5;

      candidates.push({
        score,
        href: href.slice(0, 400),
        id: parsed.id,
        vanity: parsed.vanity,
        text,
        el: a,
      });
    }

    candidates.sort((x, y) => y.score - x.score);
    const best = candidates[0];
    if (best && best.score >= 15) {
      out.profile_href = best.href;
      out.profile_id_guess = best.id || best.vanity || null;
    }

    let img =
      (best?.el && best.el.querySelector('img[src*="scontent"], img, image')) || null;
    if (!img) {
      img =
        art.querySelector('a[href*="profile.php"] img[src*="scontent"]') ||
        art.querySelector('img[src*="scontent"]') ||
        art.querySelector("image") ||
        art.querySelector("img");
    }
    if (img) {
      out.avatar_src = (
        img.getAttribute("src") ||
        img.getAttribute("xlink:href") ||
        ""
      ).slice(0, 500);
      out.avatar_alt = (img.getAttribute("alt") || "").slice(0, 120);
    }
  } catch (_) {
    /* ignore */
  }
  return out;
}

function nameHintFromCommentText(text) {
  const t = String(text || "").trim();
  if (!t) return null;
  const parts = t.split(/\s+/);
  if (parts.length < 2) return parts[0] || null;
  // 1–2 primeiras palavras = nome heurístico (só para a sonda)
  return parts.slice(0, Math.min(2, parts.length - 1)).join(" ");
}

function cleanAuthorDisplayHint(hint) {
  return String(hint || "")
    .replace(/\s*h[áa]\s+\d+\s*(min|h|hora|horas|m|s).*$/i, "")
    .replace(/\s*·\s*.*$/, "")
    .replace(/\s+/g, " ")
    .trim();
}

function rememberAuthorProbe(probe) {
  if (!probe || !probe.name_hint) return;
  chrome.storage.local.get(["psAuthorIdentitySamples"], (cfg) => {
    const list = Array.isArray(cfg.psAuthorIdentitySamples)
      ? cfg.psAuthorIdentitySamples.slice()
      : [];
    const key = `${probe.name_hint}|${probe.profile_href || ""}|${probe.profile_id_guess || ""}`;
    if (
      list.some(
        (x) =>
          `${x.name_hint}|${x.profile_href || ""}|${x.profile_id_guess || ""}` === key,
      )
    ) {
      return;
    }
    list.push(probe);
    while (list.length > 40) list.shift();
    chrome.storage.local.set({
      psAuthorIdentitySamples: list,
      psAuthorIdentityUpdatedAt: Date.now(),
    });
  });
}

function authorRefFromEl(el, text) {
  try {
    const aria = el?.getAttribute?.("aria-label") || "";
    const ariaM =
      aria.match(/Coment[aá]rio de\s+(.+)/i) ||
      aria.match(/Comment by\s+(.+)/i);
    const hint = cleanAuthorDisplayHint(
      (ariaM && stripFbUi(ariaM[1])) || nameHintFromCommentText(text),
    );
    const probe = probeAuthorIdentity(el, hint);
    rememberAuthorProbe(probe);
    return {
      authorRef: facebookBuyerRefFromProbe(probe),
      probe,
      nameHint: hint,
    };
  } catch (_) {
    return { authorRef: null, probe: null, nameHint: null };
  }
}

/** Extrai nome+corpo de UM artigo — nunca misturar com o vizinho. */
function extractFromArticle(article) {
  if (!article) return "";

  // Harness: .name + .body (contrato estável)
  const nameEl =
    article.querySelector(":scope > .name") ||
    article.querySelector(".name");
  const bodyEl =
    article.querySelector(":scope > .body") ||
    article.querySelector(".body");
  if (nameEl && bodyEl) {
    const name = stripFbUi(nameEl.textContent || "");
    const body = stripFbUi(bodyEl.textContent || "");
    if (name && body && name.length < 80 && body.length < 400) {
      const out = `${name} ${body}`;
      pushChatTrace({
        stage: "NORMALIZED",
        reason: "harness_name_body",
        text: out.slice(0, 120),
        authorHint: name,
      });
      return out;
    }
  }

  // Face: aria-label "Comentário de X" + texto do artigo (limitado)
  const aria = article.getAttribute("aria-label") || "";
  const ariaM =
    aria.match(/Coment[aá]rio de\s+(.+)/i) ||
    aria.match(/Comment by\s+(.+)/i);
  const ariaName = ariaM ? stripFbUi(ariaM[1]) : null;

  let raw = (article.innerText || article.textContent || "").trim();
  // Rejeitar mega-bloco (vários comentários colados)
  if ((raw.match(/\bResponder\b/gi) || []).length >= 2) {
    pushChatTrace({
      stage: "DROPPED",
      reason: "multi_responder_block",
      text: raw.slice(0, 80),
    });
    return "";
  }
  if (raw.length > 280) {
    // Tentar só as primeiras linhas úteis
    const lines = raw
      .split(/\n/)
      .map((l) => stripFbUi(l.trim()))
      .filter(Boolean)
      .filter(
        (l) =>
          !/^(Responder|Reply|Gosto|Like|Partilhar|Share|\d+\s*m(in)?)$/i.test(l),
      );
    if (lines.length >= 2) {
      raw = `${lines[0]} ${lines[lines.length - 1]}`;
    } else {
      pushChatTrace({
        stage: "DROPPED",
        reason: "raw_too_long_no_lines",
        text: raw.slice(0, 80),
      });
      return "";
    }
  }

  const t = normalizeFbCommentBlock(raw);
  if (!t) {
    pushChatTrace({
      stage: "DROPPED",
      reason: "normalize_empty",
      text: String(raw || "").slice(0, 120),
      authorHint: ariaName || "",
    });
    return "";
  }

  // Preferir sempre o nome do aria-label quando o texto não o traz (evita «Comprador»)
  let out = t;
  if (ariaName && ariaName.length > 2) {
    const low = t.toLowerCase();
    const aLow = ariaName.toLowerCase();
    if (!low.startsWith(aLow) && !low.includes(aLow.split(/\s+/)[0] || "___")) {
      out = `${ariaName} ${t}`;
    }
  }
  pushChatTrace({
    stage: "NORMALIZED",
    text: out.slice(0, 120),
    authorHint: ariaName || "",
  });
  return out;
}

function looksLikePersonNameLine(line) {
  const w = String(line || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (w.length < 2 || w.length > 4) return false;
  // "Mariana Soares" / "Ana Silva" — não "bla bla" / "palavras curtas..."
  return w.every((x) => /^[A-ZÀ-Ú][\p{L}'’.-]*$/u.test(x));
}

function normalizeFbCommentBlock(raw) {
  const text = (raw || "").trim();
  if (text.length > 280) return "";
  if ((text.match(/Responder/gi) || []).length >= 2) return "";
  if (/está agora em direto|Conteúdo partilhado|Comentar como/i.test(text)) return "";

  const lines = text
    .replace(/\r/g, "\n")
    .split("\n")
    .map((l) => stripFbUi(l.trim()))
    .filter(Boolean)
    .filter(
      (l) =>
        !/^(Responder|Reply|Gosto|Like|Partilhar|Share|\d+\s*m(in)?\.?)$/i.test(l) &&
        !/\d+\s*min\.?$/i.test(l) &&
        !/^\d{1,2}$/.test(l), // residual «1» após strip de «1 min»
    );
  if (lines.length === 0) return "";

  if (lines.length >= 2) {
    const nameLine = lines[0];
    const commentLine = lines[lines.length - 1];
    // Só rejeitar fusão de DOIS nomes de pessoa — NÃO chat humano multi-palavra
    // (v1.7.18 bug: «bla bla» / «palavras curtas…» eram tratados como nome e descartados)
    if (looksLikePersonNameLine(nameLine) && looksLikePersonNameLine(commentLine)) {
      return "";
    }
    if (/^[A-Za-zÀ-ú]/.test(nameLine) && commentLine) {
      if (commentLine.toLowerCase().startsWith(nameLine.toLowerCase())) {
        return commentLine;
      }
      return `${nameLine} ${commentLine}`;
    }
  }
  return stripFbUi(lines.join(" "));
}

/** id estável por comentário DOM — preferir comment_id do Face. */
function commentDomUid(el) {
  if (!el) return "";
  try {
    const a = el.querySelector?.('a[href*="comment_id="]');
    if (a) {
      const ck = decodeFbCommentKey(a.getAttribute("href") || "");
      if (ck) return ck;
    }
  } catch (_) {
    /* ignore */
  }
  return (
    el.dataset?.postedAt ||
    el.getAttribute("data-comment-id") ||
    el.getAttribute("data-testid") ||
    el.id ||
    ""
  );
}

/**
 * @returns {{ text: string, uid: string, el?: Element, authorRef?: string|null }[]}
 */
function extractCommentBlocks(root) {
  const seen = new Set();
  const out = [];
  const push = (el) => {
    const t = extractFromArticle(el);
    // Aceitar chat curto («ok», «sim») — mínimo 1 caractere útil
    if (!t || t.length < 1 || t.length >= 500) return;
    const uid = commentDomUid(el);
    const key = uid ? `${uid}|${t}` : t;
    if (seen.has(key)) return;
    seen.add(key);
    const { authorRef } = authorRefFromEl(el, t);
    out.push({ text: t, uid, el, authorRef: authorRef || null });
  };

  const articles = root.querySelectorAll('[role="article"]');
  if (articles.length) {
    articles.forEach((article) => push(article));
  }

  // Fallback Face sem role=article
  root.querySelectorAll('[data-testid*="comment" i]').forEach((node) => {
    if (node.closest('[role="article"]')) return;
    push(node);
  });

  // Deep: âncoras profile+comment_id (como v1.7.14) — NÃO filtrar dirty aqui
  for (const d of deepScanAuthorIdentities(root)) {
    const uid = d.data_attrs?.comment_key || "";
    if (uid && [...seen].some((k) => k.startsWith(`${uid}|`))) continue;
    const el = d._el;
    if (!el) continue;
    const t =
      extractFromArticle(el) ||
      `${d.name_hint || "Convidado"} comentario`;
    if (!t || t.length < 1) continue;
    const key = uid ? `${uid}|${t}` : t;
    if (seen.has(key)) continue;
    seen.add(key);
    const ref = facebookBuyerRefFromProbe(d);
    out.push({ text: t, uid, el, authorRef: ref || null });
  }

  return out;
}

/** Sonda sob pedido do popup — deep scan por comment_id (ground truth Face). */
function runAuthorIdentityProbeNow() {
  const root = document.body || document.documentElement;
  // Primário: um sample por comment_id (isola homónimos)
  const deep = deepScanAuthorIdentities(root);
  let samples = deep.map((d) => {
    const { _score, _el, ...rest } = d;
    rememberAuthorProbe(rest);
    return rest;
  });

  // Complementar com blocos article se trouxerem IDs novos
  const blocks = extractCommentBlocks(root);
  for (const b of blocks) {
    const aria = b.el?.getAttribute?.("aria-label") || "";
    const ariaM =
      aria.match(/Coment[aá]rio de\s+(.+)/i) ||
      aria.match(/Comment by\s+(.+)/i);
    const hint =
      (ariaM && stripFbUi(ariaM[1])) || nameHintFromCommentText(b.text);
    const p = probeAuthorIdentity(b.el || root, hint);
    if (!p?.profile_id_guess) continue;
    const already = samples.some(
      (s) =>
        s.profile_id_guess === p.profile_id_guess &&
        (s.data_attrs?.comment_key || "") === (p.data_attrs?.comment_key || ""),
    );
    if (!already) {
      rememberAuthorProbe(p);
      samples.push(p);
    }
  }

  // Dedup final por comment_key, senão por id+nome
  const uniq = new Map();
  for (const s of samples) {
    const k =
      s.data_attrs?.comment_key ||
      `${s.profile_id_guess}|${s.name_hint || ""}|${s.profile_href || ""}`;
    if (!uniq.has(k)) uniq.set(k, s);
  }
  samples = [...uniq.values()].slice(0, 40);

  const summary = {
    type: "ps_author_identity_probe",
    ok: true,
    at: new Date().toISOString(),
    page_url: (location.href || "").slice(0, 300),
    comment_blocks: samples.length,
    with_profile_href: samples.filter((s) => s && s.profile_href).length,
    with_profile_id: samples.filter((s) => s && s.profile_id_guess).length,
    with_avatar: samples.filter((s) => s && s.avatar_src).length,
    unique_profile_ids: [
      ...new Set(samples.map((s) => s.profile_id_guess).filter(Boolean)),
    ],
    samples,
    method: "deep_comment_id",
  };
  chrome.storage.local.set({
    psAuthorIdentitySamples: samples,
    psAuthorIdentityLastProbe: summary,
    psAuthorIdentityUpdatedAt: Date.now(),
  });
  postTelemetry(summary);
  return summary;
}

// Bridge para content_loader (sendMessage do popup)
try {
  globalThis.__fleaberPsAuthorProbe = runAuthorIdentityProbeNow;
} catch (_) {}

function isNoise(text) {
  const t = text.toLowerCase();
  if (/^(gosto|responder|partilhar|like|reply|seguir|follow)$/i.test(t)) return true;
  if (/activate\s*windows/.test(t)) return true;
  if (/^\d+\s*min$/.test(t)) return true;
  if (/\.(md|py|dart|png|pdf)\b/.test(t)) return true;
  if (/^(escreve|write)\s+(um\s+)?coment/i.test(t)) return true;
  // NÃO chamar filtros de display/OCR aqui — bloqueava pipeline (v1.7.15).
  return false;
}

/**
 * Só para DISPLAY no Studio — NUNCA usar em harvest/enqueue/parser.
 * Compact da linha inteira NÃO deve usar padrões «soares»+corpo (falso positivo).
 */
function isDirtyDisplayCandidate(text) {
  const t = String(text || "").trim();
  if (!t) return true;
  if (/\bcomentario\b/i.test(t) && t.split(/\s+/).length <= 5) return true;
  if (/\d+\s*min\.?\s*$/i.test(t)) return true;
  return false;
}

/** Cumprimentos / conversa — NÃO reservar. */
function isSocialChat(text) {
  const { name, body } = (() => {
    try {
      return splitNameBodyForChat(text);
    } catch {
      return { name: null, body: text };
    }
  })();
  const work = (body || text || "").trim().toLowerCase();
  if (!work) return true;
  // Tem pedido de compra / cancel / ref → não é chat social
  if (
    /\b(quero|queria|kero|qero|cancela|tira|retira|afinal|apenas|troca|mesminho|o\s+mesmo|tamb[eé]m|mais\s+um)\b/i.test(
      work,
    )
  ) {
    return false;
  }
  if (/\b(AM|KK|CB|CM|HS|RF|TT|FX|PT)\s*\d{1,4}\b/i.test(work)) return false;
  if (/\b\d{3}\/\d+\b/.test(work)) return false;
  if (/^\d{1,2}$/.test(work)) return false; // slot "3"
  return /^(bom\s+dia|boa\s+tarde|boa\s+noite|ola|olá|oi|hey|hello|obrigad[oa]|obrigado|valeu|ok|okay|perfeito|fixe|top|ainda\s+tem\s+stock|quanto\s+custa|podes\s+separar|ainda\s+da|fechado|fechou)([\s!.?]|$)/i.test(
    work,
  );
}

function splitNameBodyForChat(text) {
  const parts = String(text || "").trim().split(/\s+/);
  if (parts.length < 2) return { name: null, body: text };
  // Reusa heurística simples: 1–3 palavras de nome
  for (let n = Math.min(3, parts.length - 1); n >= 1; n -= 1) {
    const name = parts.slice(0, n).join(" ");
    const body = parts.slice(n).join(" ");
    if (/^[A-Za-zÀ-ú]/.test(name) && body) return { name, body };
  }
  return { name: null, body: text };
}

function refKey(parsed) {
  if (!parsed) return "";
  if (parsed.refSlug) {
    return String(parsed.refSlug).toUpperCase().replace(/^#/, "");
  }
  if (parsed.publicSlot != null) return `slot:${parsed.publicSlot}`;
  return "";
}

function qtyStoreKey(parsed, cfg) {
  const rk = refKey(parsed);
  if (!rk) return "";
  const buyerRef = resolveExternalBuyerRef(
    cfg.liveId,
    parsed?.displayName || "anon",
    parsed?.externalBuyerRef,
  );
  return `${cfg.liveId}|${buyerRef}|${rk}`;
}

function isQtyRegression(parsed, cfg) {
  if (!parsed || parsed.intent !== "reserve" || !cfg?.liveId) return false;
  if (parsed.reason === "reduce_delta" || parsed.reason === "reduce_qty") return false;
  const key = qtyStoreKey(parsed, cfg);
  if (!key) return false;
  const prev = lastQty[key];
  if (!prev) return false;
  return parsed.quantity < prev;
}

function shouldUseLlm(cfg, text, parsed) {
  // Modo REF obrigatório: sem inventar artigo via IA
  if (cfg.strictRefMode) return false;
  if (!cfg.ollamaEnabled) return false;
  if (ollamaUnreachable) {
    if (Date.now() - ollamaUnreachableAt < 20000) return false;
    ollamaUnreachable = false;
  }
  // Chat social: nunca IA (evita «bom dia» → reserva)
  if (isSocialChat(text)) return false;
  // Texto claro com ref AM/KK + qty: parser basta
  const reason = llmTriggerReason(text, parsed, cfg);
  if (
    reason === "confirmacao_ia" ||
    reason === "continuidade_mesmo_artigo" ||
    reason === "local_fast_path"
  ) {
    // Ref explícita no texto + confiança alta → sem IA
    if (
      parsed?.refSlug &&
      (parsed.parserConfidence ?? 0) >= 0.8 &&
      !parsed.needsReview &&
      parsed.reason !== "context_echo" &&
      parsed.reason !== "qty_only_supersede"
    ) {
      return false;
    }
  }
  // Só quando realmente precisa
  return [
    "sem_parse",
    "sem_parse_frio",
    "needs_review",
    "context_echo",
    "qty_only_supersede",
    "qty_regressao",
    "cancel_sem_ref",
    "ambiguo_sem_ref",
    "continuidade_comprador",
    "reduce_delta",
    "title_guess",
    "baixa_confianca",
  ].includes(reason);
}

function llmTriggerReason(text, parsed, cfg) {
  // Mantido para telemetria / mensagens do painel (já não decide skip).
  const buyer = parsed?.displayName || identity.lastValidName;
  const conf = parsed?.parserConfidence ?? 0;

  if (!parsed) {
    return identity.hasPriorContext(buyer) ? "sem_parse" : "sem_parse_frio";
  }
  if (parsed.reason === "reduce_delta") return "reduce_delta";
  if (parsed.reason === "qty_only_supersede" || parsed.reason === "continuity_last_ref") {
    return parsed.reason;
  }
  if (parsed.reason === "context_echo") return "context_echo";
  if (parsed.needsReview) return "needs_review";
  if (isQtyRegression(parsed, cfg)) return "qty_regressao";
  const hasRef = !!(parsed.refSlug || parsed.publicSlot != null);
  if (!hasRef) {
    if (parsed.intent === "cancel") return "cancel_sem_ref";
    if (identity.hasPriorContext(buyer)) return "continuidade_comprador";
    return "ambiguo_sem_ref";
  }
  if (identity.hasPriorContext(buyer)) return "continuidade_mesmo_artigo";
  if (conf < 0.98) return "baixa_confianca";
  return "confirmacao_ia";
}

function buyerQtySnapshot(cfg, buyer, authorRef = null) {
  const buyerRef = resolveExternalBuyerRef(
    cfg.liveId,
    buyer || "anon",
    authorRef,
  );
  const prefix = `${cfg.liveId}|${buyerRef}|`;
  const out = {};
  for (const [k, v] of Object.entries(lastQty)) {
    if (!k.startsWith(prefix)) continue;
    const ref = k.slice(prefix.length);
    if (ref) out[ref] = v;
  }
  return out;
}

let ollamaUnreachable = false;
let ollamaLastError = "";
let ollamaUnreachableAt = 0;

function parserFallbackAfterLlmFail(text, parsed, cfg) {
  let out = parsed ? { ...parsed } : null;
  if (!out) {
    out = parseCommentLine(text, parseOpts(cfg));
    if (!out) return null;
  }
  if (cfg.strictRefMode) {
    out = { ...out, publicSlot: null };
    if (!out.refSlug) {
      out.intent = "chat";
      out.reason = "strict_no_ref";
    }
  } else {
    out = resolveSlotToRef(out, cfg.liveCatalog || []);
  }
  out = identity.apply(out);
  out = resolveSlotToRef(out, cfg.liveCatalog || []);
  if (out && (out.refSlug || out.publicSlot != null)) {
    out.needsReview = false;
    out.reason = out.reason || "parser_fallback";
  }
  return out;
}

function sendMessage(type, payload = {}) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (v) => {
      if (settled) return;
      settled = true;
      resolve(v);
    };
    const timer = setTimeout(() => {
      finish({ ok: false, error: "ext_message_timeout_22s" });
    }, 22000);
    try {
      chrome.runtime.sendMessage({ type, ...payload }, (resp) => {
        clearTimeout(timer);
        if (chrome.runtime.lastError) {
          finish({ ok: false, error: chrome.runtime.lastError.message });
          return;
        }
        finish(resp || { ok: false, error: "empty_response" });
      });
    } catch (e) {
      clearTimeout(timer);
      finish({ ok: false, error: String(e) });
    }
  });
}

async function resolveWithLlm(text, parsed, cfg) {
  const buyer = parsed?.displayName || identity.lastValidName;
  const qtyState = buyerQtySnapshot(cfg, buyer);

  // tira com qty conhecida → aplica local; sem qty → IA COM estado (pode estar vazio)
  if (parsed?.reason === "reduce_delta" && (parsed.refSlug || parsed.publicSlot != null)) {
    const key = qtyStoreKey(parsed, cfg);
    const prev = key ? lastQty[key] : null;
    if (prev && prev > 0) {
      const reduced = await applyReduceQty(parsed, cfg);
      logPanelEvent({
        kind: "ok",
        message: "tira local (qty conhecida)",
        detail: text.slice(0, 80),
        parsed: reduced,
      });
      return reduced;
    }
    // sem prev → continua para Ollama com qtyState
  }

  const reason = llmTriggerReason(text, parsed, cfg) || "ambiguo";
  const catalog = (cfg.liveCatalog || []).map((it) => ({
    slot: it.public_slot ?? it.slot ?? null,
    ref: it.ref_code || it.ref || null,
    title: it.title || null,
    active: !!(it.is_active || it.active),
  }));
  const buyerLastRef = buyer ? identity.getBuyerLastRef(buyer) : null;
  const qtyRefs = Object.keys(qtyState);
  const activeRef =
    buyerLastRef ||
    (qtyRefs.length === 1 ? qtyRefs[0] : null) ||
    cfg.liveActiveRef ||
    null;
  const chatPack = chatPackForOllama(text, parsed);
  const resp = await sendMessage("ollama_resolve", {
    comment: text,
    catalog,
    activeRef,
    buyer,
    buyer_qty_state: qtyState,
    chat_recent: chatPack.lines,
    chat_recent_meta: {
      total_lines: chatPack.total_lines,
      sent_lines: chatPack.sent_lines,
      truncated: chatPack.truncated,
    },
  });
  if (!resp?.ok || !resp.result) {
    stats.llmMiss += 1;
    stats.lastLlm = `falhou (${reason})`;
    const err = resp?.error || "unknown";
    ollamaLastError = String(err);
    // Só marcar offline em erros de rede reais — NÃO bloquear para sempre em bad_json / modelo
    if (/fetch|network|failed|ECONNREFUSED|cors_403|http_5\d\d|http_404/i.test(String(err))) {
      ollamaUnreachable = true;
      ollamaUnreachableAt = Date.now();
      stats.lastLlm = `offline (${err})`;
    }
    console.warn("[Fleaber PS] 🤖 IA falhou", reason, text, err);
    logPanelEvent({
      kind: "warn",
      message: `🤖 IA falhou (${reason}): ${String(err).slice(0, 60)}`,
      detail: text.slice(0, 80),
      meta: { reason, error: err, raw: text.slice(0, 200), qty_state: qtyState },
    });
    const fb = parserFallbackAfterLlmFail(text, parsed, cfg);
    if (fb) {
      fb._ollama = { called: true, ok: false, error: err, reason };
    }
    return fb;
  }

  // Sucesso → reabrir circuito se estava offline
  ollamaUnreachable = false;
  ollamaLastError = "";

  const llm = resp.result;
  const intentRaw = String(llm.intent || "").toLowerCase();
  if (intentRaw !== "reserve" && intentRaw !== "cancel") {
    stats.llmMiss += 1;
    stats.lastLlm = `ignorado (${intentRaw || "chat"})`;
    if (parsed) {
      parsed._ollama = { called: true, ok: true, ignored: intentRaw || "chat", reason };
    }
    return parsed;
  }

  const parserQty = Math.max(1, Math.min(Number(parsed?.quantity) || 1, 99));
  let llmQty = Math.max(1, Math.min(Number(llm.quantity) || 1, 99));
  if (parserQty > 1 && llmQty === 1) llmQty = parserQty;

  const llmParsed = {
    intent: intentRaw === "cancel" ? "cancel" : "reserve",
    displayName: parsed?.displayName || null,
    refSlug: llm.ref_slug ? String(llm.ref_slug).trim() : null,
    publicSlot: llm.public_slot != null ? Number(llm.public_slot) : null,
    quantity: llmQty,
    rawLine: text,
    parserConfidence: Number(llm.confidence) || 0.72,
    needsReview: !!llm.needs_review,
    reason: "ollama",
  };

  const tiraM = text.match(
    /\b(?:tira|retira)(?:\s+|(?=\d))(?:me\s+)?(\d{1,2})\s+(?:ref\s*)?([A-Za-z]{1,4}\d{1,4})\b/i,
  );
  if (tiraM && llmParsed.intent === "reserve") {
    const delta = Math.max(1, Math.min(parseInt(tiraM[1], 10), 99));
    const ref = (llmParsed.refSlug || tiraM[2] || "").toUpperCase().replace(/^#/, "");
    const prev = qtyState[ref] || qtyState[tiraM[2]?.toUpperCase?.()] || null;
    if (prev != null) {
      llmParsed.quantity = Math.max(1, prev - delta);
      llmParsed.refSlug = llmParsed.refSlug || tiraM[2];
      llmParsed.reason = "reduce_qty";
      llmParsed.needsReview = false;
    } else {
      llmParsed.quantity = delta;
      llmParsed.refSlug = llmParsed.refSlug || tiraM[2];
      llmParsed.reason = "reduce_delta";
      llmParsed.needsReview = true;
    }
  }

  stats.llmUsed += 1;
  stats.lastLlm = `${reason}: ${llmParsed.intent} ${llmParsed.refSlug || llmParsed.publicSlot || "?"} qty=${llmParsed.quantity}`;
  llmParsed._ollama = {
    called: true,
    ok: true,
    reason,
    chat_recent_lines: chatPack.sent_lines,
    chat_recent_total: chatPack.total_lines,
    chat_recent_truncated: chatPack.truncated,
  };
  console.log("[Fleaber PS] 🤖 IA", reason, text, llmParsed);
  logPanelEvent({
    kind: "ok",
    message: `🤖 IA (${reason})`,
    detail: `${llmParsed.intent} ${llmParsed.refSlug || llmParsed.publicSlot || "?"} qty=${llmParsed.quantity}`,
    meta: {
      reason,
      intent: llmParsed.intent,
      ref: llmParsed.refSlug || llmParsed.publicSlot,
      qty: llmParsed.quantity,
      raw: text.slice(0, 200),
      qty_state: qtyState,
      chat_recent_lines: chatPack.sent_lines,
      chat_recent_total: chatPack.total_lines,
      chat_recent_truncated: chatPack.truncated,
    },
  });

  if (!parsed) return llmParsed;
  return {
    ...llmParsed,
    displayName: parsed.displayName || llmParsed.displayName,
  };
}

async function applyReduceQty(parsed, cfg) {
  if (!parsed || parsed.reason !== "reduce_delta") return parsed;
  const key = qtyStoreKey(parsed, cfg);
  if (!key) {
    return { ...parsed, needsReview: true, reason: "reduce_no_prev" };
  }
  const prev = lastQty[key];
  if (prev && prev > 0) {
    return {
      ...parsed,
      quantity: Math.max(1, prev - parsed.quantity),
      reason: "reduce_qty",
      parserConfidence: 0.9,
    };
  }
  // Sem qty anterior conhecida: NÃO gravar o delta como qty absoluta.
  return {
    ...parsed,
    needsReview: true,
    reason: "reduce_no_prev",
    forceSkipIngest: true,
  };
}

function skipStaleSupersede(parsed, cfg) {
  if (!parsed || parsed.intent !== "reserve" || !cfg?.liveId) return false;
  if (parsed.reason === "reduce_delta" || parsed.reason === "reduce_qty") return false;
  // REF explícita na linha = supersede intencional (também para baixar qty).
  // Sem isto, «quero 1 AM3» após «quero 4 AM3» era ignorado como "releitura".
  if (parsed.refSlug && /\b(?:ref\s*)?[a-z]{1,4}\d{1,4}\b/i.test(parsed.rawLine || "")) {
    return false;
  }
  const key = qtyStoreKey(parsed, cfg);
  if (!key) return false;
  const prev = lastQty[key];
  if (!prev || parsed.quantity >= prev) return false;
  if (/\b(afinal|so|só|tira|retira)\b/i.test(parsed.rawLine || "")) return false;
  return true;
}

async function getConfig() {
  if (!extAlive()) {
    retireStaleContentScript("getConfig");
    return {};
  }
  return new Promise((resolve) => {
    try {
      chrome.storage.local.get(
        [
          "liveId",
          "deviceToken",
          "deviceId",
          "liveTitle",
          "enabled",
          "ollamaEnabled",
          "ollamaModel",
          "liveCatalog",
          "liveActiveRef",
          "strictRefMode",
        ],
        (cfg) => {
          if (chrome.runtime.lastError) {
            const msg = chrome.runtime.lastError.message || "";
            if (/invalidated|context/i.test(msg)) {
              retireStaleContentScript(msg);
            }
            resolve({});
            return;
          }
          resolve(cfg || {});
        },
      );
    } catch (e) {
      retireStaleContentScript(String(e?.message || e));
      resolve({});
    }
  });
}

async function ingest(parsed, cfg) {
  parsed = resolveSlotToRef(parsed, cfg.liveCatalog || []);
  // Ref explícita fora do catálogo (pt99): NÃO deixar identity/lastRef trocar o artigo
  const catalogRefs = new Set(
    (cfg.liveCatalog || [])
      .map((it) => String(it.ref_code || it.ref || "").toUpperCase().replace(/^#/, ""))
      .filter(Boolean),
  );
  identity.setCatalogRefs([...catalogRefs]);
  const explicitRef = parsed.refSlug
    ? String(parsed.refSlug).toUpperCase().replace(/^#/, "")
    : "";
  const ghostRef = !!(explicitRef && catalogRefs.size && !catalogRefs.has(explicitRef));
  if (ghostRef) {
    parsed = {
      ...parsed,
      needsReview: true,
      reason: parsed.reason || "ghost_ref",
      forceKeepRef: true,
    };
  }
  const beforeId = { ...parsed };
  parsed = identity.apply(parsed);
  if (ghostRef && beforeId.refSlug) {
    parsed = { ...parsed, refSlug: beforeId.refSlug, publicSlot: null };
  }
  const name = parsed.displayName || `anon:${lineHash(parsed.rawLine).slice(0, 8)}`;
  const buyerRef = resolveExternalBuyerRef(
    cfg.liveId,
    name,
    parsed.externalBuyerRef,
  );
  const lh = lineHash(
    `${parsed.rawLine}${parsed._ingestHashSuffix || ""}`,
  );
  // NÃO marcar SEEN antes do ACK — se falhar, volta à fila.

  seq += 1;
  const ollamaMeta = parsed._ollama || {
    called: false,
    ok: null,
    reason: cfg.ollamaEnabled ? "skipped_or_local" : "checkbox_off",
  };
  const payload = {
    live_id: cfg.liveId,
    ref_slug: parsed.refSlug,
    public_slot: parsed.publicSlot,
    requested_qty: parsed.quantity,
    external_display_name: parsed.displayName,
    external_buyer_ref: buyerRef,
    ocr_raw_line: parsed.rawLine,
    ocr_line_hash: lh,
    detected_at: new Date().toISOString(),
    chat_sequence: seq,
    avatar_phash: "ext",
    ocr_confidence: 0.95,
    parser_confidence: parsed.parserConfidence,
    identity_confidence: /^fb:/.test(buyerRef)
      ? 0.95
      : parsed.displayName
        ? 0.88
        : 0.45,
    parser_intent: parsed.intent,
    device_id: cfg.deviceId || "ps-chrome-ext",
    force_needs_review: parsed.needsReview || !parsed.displayName,
  };

  const resp = await sendMessage("ingest", { payload });
  const journalBase = {
    live_id: cfg.liveId,
    chat_sequence: seq,
    buyer: parsed.displayName,
    intent: parsed.intent,
    ref_in: parsed.refSlug,
    slot_in: parsed.publicSlot,
    qty_in: parsed.quantity,
    raw: parsed.rawLine,
    ollama_enabled: !!cfg.ollamaEnabled,
    ollama_called: !!ollamaMeta.called,
    ollama_ok: ollamaMeta.ok,
    ollama_reason: ollamaMeta.reason || null,
    ollama_error: ollamaMeta.error || null,
  };
  if (resp?.ok) {
    SEEN.add(lh);
    // TTL so for plain-text keys (no comment uid) — same rule as markSeen().
    const commentUid = String(parsed?._commentUid || "");
    if (!commentUid) seenTextAt.set(lh, Date.now());
    QUEUED.delete(lh);
    stats.ingested += 1;
    stats.lastAction = resp.action || "created";
    stats.lastError = "";
    const resolvedRef =
      (resp.resolved_ref_slug || resp.ref_slug || parsed.refSlug || "")
        .toString()
        .toUpperCase()
        .replace(/^#/, "") || refKey(parsed);
    const qk = qtyStoreKey(
      { ...parsed, refSlug: resolvedRef || parsed.refSlug },
      cfg,
    );
    const qtyFinal =
      resp.requested_qty != null
        ? Number(resp.requested_qty)
        : parsed.quantity;
    if (qk && parsed.intent === "reserve" && qtyFinal > 0) {
      lastQty[qk] = Math.max(1, qtyFinal);
    } else if (qk && parsed.intent === "cancel") {
      delete lastQty[qk];
    }
    console.log("[Fleaber PS]", stats.lastAction, parsed.rawLine, resp);
    void appendStepJournal({
      ...journalBase,
      ok: true,
      action: stats.lastAction,
      ref_out: resolvedRef || null,
      qty_out: qtyFinal,
    });
    postTelemetry({
      ...journalBase,
      ok: true,
      action: stats.lastAction,
      ref_out: resolvedRef || null,
      qty_out: qtyFinal,
      ...ceoTelemetryExtras({
        parsed,
        ollamaMeta,
        ok: true,
        refOut: resolvedRef || null,
        qtyOut: qtyFinal,
        action: stats.lastAction,
      }),
    });
    logPanelEvent({
      kind: "ok",
      message: `${stats.lastAction}: ${parsed.refSlug || parsed.publicSlot || "?"} qty=${resp.requested_qty ?? parsed.quantity}${ollamaMeta.called ? (ollamaMeta.ok ? " · IA✓" : " · IA✗") : ""}`,
      detail: parsed.rawLine.slice(0, 100),
      parsed,
      meta: {
        action: stats.lastAction,
        intent: parsed.intent,
        ref: parsed.refSlug || parsed.publicSlot,
        qty: resp.requested_qty ?? parsed.quantity,
        chat_sequence: seq,
        ollama: ollamaMeta,
      },
    });
    return true;
  }

  QUEUED.delete(lh);
  stats.lastError = resp?.error || "ingest_failed";
  console.warn("[Fleaber PS] ingest fail", stats.lastError, parsed.rawLine);
  const errStr = String(stats.lastError || "");
  const permanent = PERMANENT_INGEST_ERRORS.test(errStr);
  const channelDead =
    /message channel closed|ext_message_timeout|Receiving end does not exist|context invalidated/i.test(
      errStr,
    );
  const transient =
    !permanent &&
    (channelDead ||
      /timeout|546|502|503|504|429|WORKER|aborted/i.test(errStr));

  // Definitivo (live_ended, item_not_found, …): marcar visto — sem retry infinito.
  if (permanent) {
    const seenKey = parsed._commentUid
      ? `${parsed._commentUid}\0${parsed.rawLine}`
      : parsed.rawLine;
    markSeen(seenKey);
    SEEN.add(lh);
  }

  // Falha transitória: voltar à fila já (não esperar só pelo próximo harvest).
  if (transient) {
    const raw = String(parsed.rawLine || "");
    const uid = String(parsed._commentUid || "");
    setTimeout(() => {
      try {
        enqueueText(raw, uid);
        void getConfig().then((c) => {
          if (c?.enabled) void pumpWorkers(c);
        });
      } catch (_) {}
    }, channelDead ? 1200 : 800);
    logPanelEvent({
      kind: "warn",
      message: `RETRIED fila: ${errStr.slice(0, 60)}`,
      detail: raw.slice(0, 100),
    });
  }
  void appendStepJournal({
    ...journalBase,
    ok: false,
    error: stats.lastError,
    permanent: !!permanent,
  });
  postTelemetry({
    ...journalBase,
    ok: false,
    error: stats.lastError,
    permanent: !!permanent,
    ...ceoTelemetryExtras({
      parsed,
      ollamaMeta,
      ok: false,
      error: stats.lastError,
      refOut: parsed.refSlug || null,
      qtyOut: parsed.quantity ?? null,
    }),
  });
  logPanelEvent({
    kind: "err",
    message: `Erro ingest: ${stats.lastError}`,
    detail: parsed.rawLine.slice(0, 100),
    parsed,
    meta: {
      error: stats.lastError,
      permanent: !!permanent,
      chat_sequence: seq,
      ollama: ollamaMeta,
    },
  });
  return false;
}

/** Sem comment_id o texto igual («quero rr1») bloqueava para sempre — re-quero após cancel falhava. */
const SEEN_TEXT_TTL_MS = 25000;
const seenTextAt = new Map();

function enqueueText(text, uid = "", authorRef = null) {
  const canonical = normalizeOcrLine(String(text || ""));
  if (!canonical) return;
  const dedupeKey = uid ? `${uid}\0${canonical}` : canonical;
  const lh = lineHash(dedupeKey);
  if (QUEUED.has(lh)) return;
  if (uid) {
    if (SEEN.has(lh)) return;
  } else if (SEEN.has(lh)) {
    const at = seenTextAt.get(lh) || 0;
    if (Date.now() - at < SEEN_TEXT_TTL_MS) return;
    SEEN.delete(lh);
    seenTextAt.delete(lh);
  }
  QUEUED.add(lh);
  workQueue.push({ text: canonical, uid, lh, authorRef: authorRef || null });
  stats.queueDepth = workQueue.length;
}

/**
 * Só lê o DOM e enfileira — nunca espera pela IA/ingest.
 * Assim comentários novos nao se perdem enquanto workersBusy.
 */
function harvestDomComments() {
  const roots = findChatRoots();
  stats.rootsFound = roots.length;
  let blockCount = 0;
  let enqueued = 0;
  for (const root of roots) {
    for (const block of extractCommentBlocks(root)) {
      blockCount += 1;
      const text = block.text;
      const aria = block.el?.getAttribute?.("aria-label") || "";
      const ariaM =
        aria.match(/Coment[aá]rio de\s+(.+)/i) ||
        aria.match(/Comment by\s+(.+)/i);
      const authorHint = ariaM ? stripFbUi(ariaM[1]) : null;
      pushChatTrace({
        stage: "CAPTURED",
        text: String(text || "").slice(0, 120),
        uid: block.uid || "",
        authorHint: authorHint || "",
      });
      if (isNoise(text)) {
        pushChatTrace({
          stage: "DROPPED",
          reason: "isNoise",
          text: String(text || "").slice(0, 120),
          uid: block.uid || "",
        });
        continue;
      }
      appendChatTranscript(text, block.uid || "", authorHint);
      stats.lastBlock = text.slice(0, 120);
      const before = workQueue.length;
      enqueueText(text, block.uid || "", block.authorRef || null);
      if (workQueue.length > before) {
        enqueued += 1;
        pushChatTrace({
          stage: "ENQUEUED",
          text: String(text || "").slice(0, 120),
          uid: block.uid || "",
        });
      }
    }
  }
  stats.blocksSeen = blockCount;
  stats.queueDepth = workQueue.length;
  return { blockCount, enqueued };
}

/** Garante Chat humano quando não há acção comercial (journal + transcript + TRACE). */
function ensureHumanChatEntry(cfg, text, commentUid, lh, buyerHint) {
  stats.skipped += 1;
  markSeen(commentUid ? `${commentUid}\0${text}` : text);
  QUEUED.delete(lh);
  let buyer = buyerHint || null;
  if (!buyer) {
    try {
      buyer = parseCommentLine(text)?.displayName || null;
    } catch (_) {
      /* ignore */
    }
  }
  if (!buyer) {
    try {
      const split = splitNameBodyForChat(text);
      if (split?.name && split?.body && split.body !== text) buyer = split.name;
    } catch (_) {
      /* ignore */
    }
  }
  void appendStepJournal({
    live_id: cfg.liveId,
    buyer,
    intent: "chat",
    raw: text,
    ok: true,
    action: "skipped_chat",
    comment_uid: commentUid || null,
  });
  appendChatTranscript(text, commentUid || "", buyer);
  pushChatTrace({
    stage: "JOURNAL_CHAT",
    text: String(text || "").slice(0, 120),
    buyer: buyer || "",
    uid: commentUid || "",
  });
  logPanelEvent({
    kind: "ok",
    message: "Chat (sem reserva)",
    detail: String(text || "").slice(0, 80),
    parsed: { rawLine: text, intent: "chat", displayName: buyer },
  });
}

async function processOneComment(item, cfg) {
  const text = typeof item === "string" ? item : item?.text || "";
  const commentUid = typeof item === "string" ? "" : item?.uid || "";
  const authorRef =
    typeof item === "string" ? null : item?.authorRef || null;
  const lh =
    typeof item === "object" && item?.lh
      ? item.lh
      : lineHash(commentUid ? `${commentUid}\0${text}` : text);

  // Cumprimentos / conversa → nunca inventar reserva
  if (isSocialChat(text)) {
    const pChat = parseCommentLine(text);
    ensureHumanChatEntry(
      cfg,
      text,
      commentUid,
      lh,
      pChat?.displayName || null,
    );
    postTelemetry({
      t: new Date().toISOString(),
      live_id: cfg.liveId,
      buyer: pChat?.displayName || null,
      intent: "chat",
      raw: text,
      ok: true,
      action: "skipped_chat",
      ollama_called: false,
      ceo_resultado: "chat_ignorado",
      ceo_comentario: text.slice(0, 140),
    });
    return;
  }

  let parsedList = expandMultiItemParses(text, parseOpts(cfg));
  if (!parsedList.length) {
    const one = parseCommentLine(text, parseOpts(cfg));
    parsedList = one ? [one] : [null];
  }

  let anyOk = false;
  let itemIdx = 0;
  for (let parsed of parsedList) {
    itemIdx += 1;
    if (parsed && authorRef) {
      parsed = { ...parsed, externalBuyerRef: authorRef };
    }
    if (!parsed) {
      if (!shouldUseLlm(cfg, text, null)) {
        // v1.7.18 bug: continue silencioso → «teste»/«bla bla» sem journal se harvest falhasse
        ensureHumanChatEntry(cfg, text, commentUid, lh, null);
        continue;
      }
      parsed = await resolveWithLlm(text, null, cfg);
      if (!parsed) {
        ensureHumanChatEntry(cfg, text, commentUid, lh, null);
        continue;
      }
      if (authorRef) parsed = { ...parsed, externalBuyerRef: authorRef };
      if (parsed.intent === "chat") {
        ensureHumanChatEntry(
          cfg,
          text,
          commentUid,
          lh,
          parsed.displayName || null,
        );
        continue;
      }
      parsed = identity.apply(parsed);
      if (cfg.strictRefMode) {
        parsed = { ...parsed, publicSlot: null };
        if (!parsed.refSlug) {
          parsed.intent = "chat";
          parsed.reason = "strict_no_ref";
        }
      } else {
        parsed = resolveSlotToRef(parsed, cfg.liveCatalog || []);
      }
    } else {
      const explicitRef = !!(parsed.refSlug && String(parsed.refSlug).trim());
      if (cfg.strictRefMode) {
        parsed = { ...parsed, publicSlot: null };
        if (!explicitRef && parsed.intent !== "chat") {
          parsed = {
            ...parsed,
            intent: "chat",
            reason: "strict_no_ref",
          };
        }
      } else {
        parsed = resolveSlotToRef(parsed, cfg.liveCatalog || []);
      }
      parsed = identity.apply(parsed);
      if (cfg.strictRefMode) {
        // Sem herdar REF de continuidade / contexto
        if (
          !explicitRef ||
          parsed.reason === "continuity_last_ref" ||
          parsed.reason === "context_echo" ||
          parsed.reason === "qty_only_supersede"
        ) {
          if (!explicitRef) {
            parsed = {
              ...parsed,
              intent: "chat",
              refSlug: null,
              publicSlot: null,
              reason: "strict_no_ref",
            };
          }
        } else {
          parsed = { ...parsed, publicSlot: null };
        }
      } else {
        parsed = resolveSlotToRef(parsed, cfg.liveCatalog || []);
      }
      if (parsed.reason === "reduce_delta" && (parsed.refSlug || parsed.publicSlot != null)) {
        const key = qtyStoreKey(parsed, cfg);
        const prev = key ? lastQty[key] : null;
        if (prev && prev > 0) {
          parsed = await applyReduceQty(parsed, cfg);
        } else if (shouldUseLlm(cfg, text, parsed)) {
          parsed = await resolveWithLlm(text, parsed, cfg);
          parsed = identity.apply(parsed);
          parsed = resolveSlotToRef(parsed, cfg.liveCatalog || []);
          if (parsed?.reason === "reduce_delta") {
            parsed = await applyReduceQty(parsed, cfg);
          }
        } else {
          parsed = await applyReduceQty(parsed, cfg);
        }
      } else if (shouldUseLlm(cfg, text, parsed)) {
        parsed = await resolveWithLlm(text, parsed, cfg);
        if (parsed?.intent === "chat") {
          ensureHumanChatEntry(
            cfg,
            text,
            commentUid,
            lh,
            parsed.displayName || null,
          );
          continue;
        }
        parsed = identity.apply(parsed);
        parsed = resolveSlotToRef(parsed, cfg.liveCatalog || []);
        if (parsed?.reason === "reduce_delta") {
          parsed = await applyReduceQty(parsed, cfg);
        }
      } else if (parsed) {
        parsed._ollama = {
          called: false,
          ok: null,
          reason: cfg.ollamaEnabled ? "local_fast_path" : "checkbox_off",
        };
      }
    }
    if (!parsed) {
      ensureHumanChatEntry(cfg, text, commentUid, lh, null);
      continue;
    }
    if (parsed.intent === "chat") {
      ensureHumanChatEntry(
        cfg,
        text,
        commentUid,
        lh,
        parsed.displayName || null,
      );
      continue;
    }
    stats.parsed += 1;

    if (parsed.reason === "reduce_delta") {
      parsed = await applyReduceQty(parsed, cfg);
    }
    if (parsed.forceSkipIngest || parsed.reason === "reduce_no_prev") {
      stats.skipped += 1;
      markSeen(parsed.rawLine);
      QUEUED.delete(lh);
      logPanelEvent({
        kind: "warn",
        message: "tira ignorado (sem qty anterior)",
        detail: parsed.rawLine.slice(0, 80),
        parsed,
      });
      continue;
    }
    let withId = identity.apply(parsed);
    withId = {
      ...withId,
      _commentUid: commentUid,
      externalBuyerRef: authorRef || withId.externalBuyerRef || null,
    };

    if (skipStaleSupersede(withId, cfg)) {
      stats.skipped += 1;
      console.log("[Fleaber PS] ○ Ignorado (releitura_antiga)", withId.rawLine);
      continue;
    }

    if (
      withId.intent === "reserve" &&
      !withId.refSlug &&
      withId.publicSlot == null &&
      !withId.needsReview &&
      !identity.lastValidName
    ) {
      stats.skipped += 1;
      continue;
    }

    // Multi-item: hash único por ref (senão 2º item da linha é ignorado)
    // + uid DOM: dois «quero 1 AM1» distintos não colidem no ocr_line_hash
    const suffixParts = [];
    if (commentUid) suffixParts.push(`u:${commentUid}`);
    if (parsedList.length > 1 && withId.refSlug) {
      suffixParts.push(`${String(withId.refSlug).toUpperCase()}|${itemIdx}`);
    }
    if (suffixParts.length) {
      withId = {
        ...withId,
        _ingestHashSuffix: `|${suffixParts.join("|")}`,
      };
    }

    const ok = await ingest(withId, cfg);
    if (ok) anyOk = true;
    // Multi-ref (AM4+AM5+AM6): pausa entre ingests para não derrubar Edge Function (http_546).
    if (parsedList.length > 1 && itemIdx < parsedList.length - 1) {
      await new Promise((r) => setTimeout(r, 450));
    }
  }
  if (!anyOk) {
    QUEUED.delete(lh);
  }
}

async function pumpWorkers(cfg) {
  while (workersBusy < MAX_WORKERS && workQueue.length) {
    const item = workQueue.shift();
    stats.queueDepth = workQueue.length;
    workersBusy += 1;
    void (async () => {
      try {
        await processOneComment(item, cfg);
      } finally {
        workersBusy -= 1;
        stats.queueDepth = workQueue.length;
        reportStats();
        if (workQueue.length) void pumpWorkers(cfg);
      }
    })();
  }
}

async function scan() {
  if (!extAlive()) {
    retireStaleContentScript("scan");
    return;
  }
  // Harvest DOM SEMPRE que a leitura esta activa — mesmo com workers ocupados.
  // Sem isto, comentarios novos perdem-se enquanto a IA processa a fila.
  const runPeek = getHarnessRunState();
  const harnessReading =
    runPeek.isHarness &&
    (runPeek.active || runPeek.reason === "awaiting_extension");
  const faceReading = !runPeek.isHarness && stats.active;
  if (harnessReading || faceReading) {
    try {
      harvestDomComments();
    } catch (_) {
      /* ignore */
    }
  }

  if (scanInFlight) {
    reportStats();
    return;
  }
  scanInFlight = true;
  try {
    const cfg = await getConfig();
    if (!extAlive()) return;
    stats.active = !!(cfg.enabled && cfg.liveId && cfg.deviceToken);
    if (!stats.active) {
      reportStats();
      return;
    }

    const run = getHarnessRunState();
    stats.harnessMode = !!run.isHarness;
    stats.harnessWaiting = !!(run.isHarness && !run.active);

    // Nova corrida no harness → limpa memória da anterior (não misturar logs/filas).
    if (run.isHarness && run.runId && run.runId !== lastHarnessRunId) {
      lastHarnessRunId = run.runId;
      if (run.active) {
        resetRunMemory("Nova bateria");
        clearPanelJournal();
        appendPanelEvent({
          kind: "ok",
          message: "Nova bateria — estado anterior limpo",
          detail: run.runId,
        });
      }
    }

    const harnessAwaiting =
      run.isHarness && !run.active && run.reason === "awaiting_extension";
    if (run.isHarness && !run.active && !harnessAwaiting) {
      // Pausa manual / terminado: só drena fila existente.
      if (workQueue.length || workersBusy) {
        drainUntil = Date.now() + 8000;
        stats.lastAction = `A drenar fila (${workQueue.length})`;
        await pumpWorkers(cfg);
      } else if (Date.now() < drainUntil) {
        stats.lastAction = "A confirmar fecho…";
      } else {
        stats.lastAction =
          run.reason === "run_complete"
            ? "Bateria terminada — leitura parada"
            : "A aguardar Correr";
      }
      reportStats();
      return;
    }
    if (harnessAwaiting) {
      stats.lastAction = `A processar restantes (fila ${workQueue.length})`;
      // Ultimo passe no DOM antes de esvaziar a fila
      harvestDomComments();
    }

    stats.scans += 1;
    harvestDomComments();
    await pumpWorkers(cfg);
    reportStats();
  } finally {
    scanInFlight = false;
  }
}

function rootsStillLive(roots) {
  try {
    return (roots || []).some((r) => r && r.isConnected);
  } catch (_) {
    return false;
  }
}

function refreshObserver() {
  const roots = findChatRoots();
  const key = roots.map((r) => r.tagName + (r.getAttribute("role") || "")).join("|");
  // Face remonta o chat ao voltar ao separador — nós antigos ficam detached
  // com a mesma key; sem rebind a leitura morre embora o painel diga ON.
  const needRebind =
    !observer || key !== lastRootKey || !rootsStillLive(roots);
  if (!needRebind) return;
  lastRootKey = key;
  if (observer) observer.disconnect();
  observer = new MutationObserver(() => void scan());
  roots.forEach((root) => {
    observer.observe(root, { childList: true, subtree: true, characterData: true });
  });
  console.log("[Fleaber PS] observer activo —", roots.length, "zona(s) chat");
}

/** Após trocar de separador o Face deixa de emitir mutations e o timer fica throttled. */
function resumeFaceReading(reason) {
  if (!extAlive()) return;
  lastRootKey = "";
  refreshObserver();
  void scan();
  setPanelStatus("Separador activo — a ler chat Face");
  logPanelEvent({
    kind: "ok",
    message: "Leitura retomada",
    detail: String(reason || "focus").slice(0, 40),
  });
}

function startObserver() {
  ensurePanel();
  if (timer) {
    void scan();
    reportStats();
    setPanelStatus(statusLine());
    return;
  }
  timer = setInterval(() => {
    if (!extAlive()) {
      retireStaleContentScript("interval");
      return;
    }
    refreshObserver();
    void scan();
    setPanelStatus(statusLine());
  }, 900);
  refreshObserver();
  void scan();
  console.log("[Fleaber PS] extensão activa —", location.href);
  reportStats();
  const run = getHarnessRunState();
  setPanelStatus(
    run.isHarness
      ? "Harness: emparelhado. Clica «Correr» para a extensão ler."
      : "Script activo nesta página Face",
  );
  logPanelEvent({
    kind: "ok",
    message: run.isHarness
      ? "Painel activo — só lê depois de «Correr»"
      : "Painel activo — podes arrastar pelo título",
  });
}

function startFleaberPs() {
  startObserver();
}

/** Lab v2 ↔ painel: separador Passos (Confirmar / BD). */
function onLabQaMessage(ev) {
  if (!extAlive()) return;
  const d = ev?.data;
  if (!d || d.source !== "fleaber-lab") return;
  if (d.type === "qa_prompt") {
    showQaPrompt(d.payload || {});
  } else if (d.type === "qa_bd") {
    setQaBdResult(d.payload?.text || "", d.payload?.kind || "");
  } else if (d.type === "qa_clear") {
    clearQaPrompt();
  } else if (d.type === "qa_tab") {
    selectPanelTab(d.payload?.tab || "passos");
  }
}

window.addEventListener("message", onLabQaMessage);

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startObserver);
} else {
  startObserver();
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") {
    resumeFaceReading("visibility");
  }
});
window.addEventListener("focus", () => resumeFaceReading("focus"));
window.addEventListener("pageshow", () => resumeFaceReading("pageshow"));

try {
  chrome.storage.onChanged.addListener((changes) => {
    if (!extAlive()) {
      retireStaleContentScript("storage.onChanged");
      return;
    }
    if (changes.ollamaEnabled) {
      // Religar circuito quando o utilizador (re)activa a IA
      ollamaUnreachable = false;
      ollamaLastError = "";
    }
    if (
      changes.enabled ||
      changes.liveId ||
      changes.deviceToken ||
      changes.ollamaEnabled ||
      changes.liveCatalog ||
      changes.strictRefMode ||
      changes.psRunResetToken
    ) {
      resetRunMemory(changes.psRunResetToken ? "Corrida limpa" : "Config mudou");
      if (changes.psRunResetToken) {
        lastHarnessRunId = null;
        clearPanelJournal();
        appendPanelEvent({ kind: "ok", message: "Estado da corrida limpo" });
      }
      lastRootKey = "";
      refreshObserver();
      void scan();
    }
  });
} catch (e) {
  retireStaleContentScript(String(e?.message || e));
}

export { startFleaberPs, runAuthorIdentityProbeNow };