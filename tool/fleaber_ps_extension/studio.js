/**
 * Fleaber Seller Studio — UI desktop v1.7.29 (Produção).
 * MVP: Chat do Studio = só reservas Face (chat social FB pós-MVP).
 */
const SUPABASE_URL =
  (window.FLEABER_STUDIO_ENV && window.FLEABER_STUDIO_ENV.supabaseUrl) ||
  "https://bpmpkzwnrbmuqnhgdscf.supabase.co";
const HUB_WEB_ORIGIN =
  (window.FLEABER_STUDIO_ENV && window.FLEABER_STUDIO_ENV.hubWebOrigin) ||
  "https://fleaber.pt";
const APP_VERSION_LABEL = `v${(window.FLEABER_STUDIO_ENV && window.FLEABER_STUDIO_ENV.version) || "1.7.29"} (${(window.FLEABER_STUDIO_ENV && window.FLEABER_STUDIO_ENV.label) || "production"})`;

/** Chaves operacionais da live — limpar sem tocar no login vendedor nem no histórico. */
const OPS_STORAGE_KEYS = [
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
  "psChatTranscript",
  "psChatTranscriptCount",
  "psChatTranscriptUpdatedAt",
  "psChatTrace",
  "psChatTraceUpdatedAt",
  "psAuthorIdentitySamples",
  "psAuthorIdentityLastProbe",
  "psRunResetToken",
  "liveDurationSnapshotSec",
  "liveDurationSnapshotAt",
];

const HISTORY_STORAGE_KEY = "studioLiveHistory";
const HISTORY_MAX = 40;

const PS_AI_TIERS = {
  lite: { ollamaModel: "fleaber-ps-lite" },
  pro: { ollamaModel: "fleaber-ps-pro" },
};

let hubBundle = null;
let hubMetrics = null;
let hlsPlayer = null;
let historyHlsPlayer = null;
let lastMuxUrl = "";
let lastMuxIsLive = false;
let liveEdgeKeepAliveTimer = null;
let hubRefreshing = false;
let sellerQueueRows = [];
let sellerSession = null;
let sellerProfile = null;
let sellerLoginFormOpen = false;
let queueBusy = false;
let archiveBusy = false;
/** Consulta histórica (nunca reativa PS / emparelhamento). */
let historyViewLiveId = null;
let historyViewBundle = null;
let historyListCache = [];
let historyLoading = false;

function sellerDisplayName() {
  const name = String(sellerProfile?.full_name || "").trim();
  if (name) return name;
  const email = String(sellerSession?.email || "").trim();
  if (email) return email.split("@")[0];
  const handle = String(
    sellerProfile?.handle || hubBundle?.hubLive?.seller_handle || "",
  ).trim();
  if (handle) return `@${handle}`;
  return "Conta ligada";
}

/** Sessão JWT vs dono do directo emparelhado — fila exige match. */
function sellerSessionOwnsLive() {
  const liveSeller = String(
    hubBundle?.hubLive?.seller_id || hubBundle?.hubLive?.vendedor_id || "",
  ).trim();
  const sessionId = String(sellerSession?.userId || "").trim();
  if (!sessionId || !liveSeller) return null; // desconhecido
  return sessionId === liveSeller;
}

function resolveOllamaModel(tier, storedModel) {
  const t = String(tier || "auto").toLowerCase();
  if (t === "pro") return PS_AI_TIERS.pro.ollamaModel;
  if (t === "lite") return PS_AI_TIERS.lite.ollamaModel;
  if (storedModel && /fleaber-ps-(lite|pro)/.test(storedModel)) return storedModel;
  return PS_AI_TIERS.lite.ollamaModel;
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
    live_item_id: it.live_item_id || it.id || null,
    public_slot: it.public_slot ?? it.slot ?? null,
    ref_code: it.ref_code || it.ref || null,
    title: it.title || null,
    quantity: it.quantity ?? null,
    status: it.status || null,
    is_active: !!(it.is_active || it.active),
  }));
}

function activeRefFromContext(ctx) {
  const items = Array.isArray(ctx?.items) ? ctx.items : [];
  const active = items.find((it) => it.is_active || it.active);
  return active?.ref_code || active?.ref || ctx?.active_ref || null;
}

function isFacebookUrl(url) {
  try {
    const u = new URL(url);
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

function setMsg(el, html, cls) {
  if (!el) return;
  el.className = "status-msg" + (cls ? ` ${cls}` : "");
  el.innerHTML = html || "";
}

function setLed(el, mode) {
  if (!el) return;
  el.className = "led" + (mode ? ` ${mode}` : "");
}

function formatClock(d = new Date()) {
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  const mo = String(d.getMonth() + 1).padStart(2, "0");
  return `${hh}:${mm} · ${dd}/${mo}/${d.getFullYear()}`;
}

function formatTimeShort(iso) {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "—";
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  } catch (_) {
    return "—";
  }
}

function formatDuration(sec) {
  if (sec == null || sec < 0) return null;
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function formatEuro(v) {
  if (v == null || Number.isNaN(v)) return "—";
  return `${Number(v).toFixed(2).replace(".", ",")} €`;
}

/** Estados técnicos → linguagem vendedora. */
function humanLiveStatus(status) {
  const s = String(status || "").toLowerCase();
  if (s === "ended" || s === "cancelled" || s === "canceled") return "Terminada";
  if (s === "live") return "Em directo";
  if (s === "draft" || s === "scheduled") return "Por iniciar";
  if (!s) return "Terminada";
  return status;
}

function setPanelEmpty(panelKey, showEmpty) {
  const empty = document.getElementById(`${panelKey}Empty`);
  const card = document.getElementById(`${panelKey}Card`);
  if (empty) empty.classList.toggle("hidden", !showEmpty);
  if (card) card.classList.toggle("hidden", !!showEmpty);
}

function syncEmptyPanels(hasLive) {
  setPanelEmpty("produtos", !hasLive);
  setPanelEmpty("reservas", !hasLive);
  setPanelEmpty("analises", !hasLive);
}

function updateTopbarActions(paired) {
  // Uma só acção principal de desemparelhar (topo). Painel Face não duplica.
  document.getElementById("btnUnpairTop")?.classList.toggle("hidden", !paired);
  document.getElementById("btnUnpair")?.classList.add("hidden");
}

function formatDatePt(iso) {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "—";
    const dd = String(d.getDate()).padStart(2, "0");
    const mo = String(d.getMonth() + 1).padStart(2, "0");
    const yy = d.getFullYear();
    const hh = String(d.getHours()).padStart(2, "0");
    const mm = String(d.getMinutes()).padStart(2, "0");
    return `${dd}/${mo}/${yy} ${hh}:${mm}`;
  } catch (_) {
    return "—";
  }
}

async function loadLocalHistory() {
  const raw = await chrome.storage.local.get([HISTORY_STORAGE_KEY]);
  return Array.isArray(raw[HISTORY_STORAGE_KEY]) ? raw[HISTORY_STORAGE_KEY] : [];
}

async function saveLocalHistory(list) {
  const trimmed = (Array.isArray(list) ? list : []).slice(0, HISTORY_MAX);
  await chrome.storage.local.set({ [HISTORY_STORAGE_KEY]: trimmed });
  return trimmed;
}

async function upsertLocalHistoryEntry(entry) {
  if (!entry?.liveId) return;
  const list = await loadLocalHistory();
  const idx = list.findIndex((e) => e.liveId === entry.liveId);
  if (idx >= 0) {
    list[idx] = {
      ...list[idx],
      ...entry,
      durationSec:
        entry.durationSec != null ? entry.durationSec : list[idx].durationSec,
      snapshot: entry.snapshot || list[idx].snapshot || null,
    };
  } else {
    list.unshift(entry);
  }
  await saveLocalHistory(list);
}

async function clearOpsStorage() {
  stopLiveEdgeKeepAlive();
  setMuxLivePill(false);
  lastMuxIsLive = false;
  await chrome.storage.local.remove(OPS_STORAGE_KEYS);
  hubBundle = null;
  hubMetrics = null;
  sellerQueueRows = [];
  lastMuxUrl = "";
  attachMux("", false);
}

/**
 * Live terminada deixa de ser contexto operacional: congela duração + snapshot
 * (chat FB, journal, fila, produtos) no Histórico; limpa ops activas.
 * Login vendedor e histórico comercial preservados.
 */
async function archiveAndClearOpsLive(hubLive, metrics, cfg) {
  if (archiveBusy) return false;
  const Hub = window.FleaberStudioHub;
  if (!Hub || !hubLive?.id) return false;
  archiveBusy = true;
  try {
    const frozen =
      cfg?.liveDurationSnapshotSec != null &&
      Number.isFinite(Number(cfg.liveDurationSnapshotSec))
        ? Math.max(0, Math.floor(Number(cfg.liveDurationSnapshotSec)))
        : null;
    const entry = Hub.buildHistoryEntry({
      hubLive,
      metrics,
      frozenDurationSec: frozen,
      archivedAt: new Date().toISOString(),
      snapshot: {
        chatTranscript: Array.isArray(cfg?.psChatTranscript)
          ? cfg.psChatTranscript
          : [],
        journal: Array.isArray(cfg?.psStepJournal) ? cfg.psStepJournal : [],
        queueRows: Array.isArray(sellerQueueRows) ? sellerQueueRows : [],
        products: Array.isArray(hubBundle?.products) ? hubBundle.products : [],
        liveMessages: Array.isArray(hubBundle?.liveMessages)
          ? hubBundle.liveMessages
          : [],
      },
    });
    if (entry) await upsertLocalHistoryEntry(entry);
    await clearOpsStorage();
    setOpsMsg(
      "Directo terminado — dashboard limpo. Consulta no Histórico (só leitura).",
      "warn",
    );
    return true;
  } finally {
    archiveBusy = false;
  }
}

function setOpsEmptyVisible(show) {
  const empty = document.getElementById("opsEmptyState");
  const grid = document.getElementById("opsGrid");
  if (empty) empty.classList.toggle("hidden", !show);
  if (grid) grid.classList.toggle("hidden", !!show);
  document.getElementById("panel-direto")?.classList.toggle("is-empty", !!show);
}

function setOpsMsg(html, cls) {
  setMsg(document.getElementById("statusMsg"), html, cls);
  setMsg(document.getElementById("statusMsgEmpty"), html, cls);
}

function clearOpsDashboardUi() {
  const wipe = (id, html = "") => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = html;
  };
  wipe("prodStrip", "");
  wipe("prodGrid", "");
  wipe("opsKpiRow", "");
  wipe("opsAnalytics", "");
  wipe("alertsList", "");
  wipe("kpiRow", "");
  wipe("activityFeed", "");
  wipe("liveChatFeed", "");
  const chatMeta = document.getElementById("liveChatMeta");
  if (chatMeta) chatMeta.textContent = "—";
  const ap = document.getElementById("activeProductCard");
  if (ap) {
    ap.classList.add("hidden");
    ap.innerHTML = "";
  }
  document.getElementById("prodStripMeta").textContent = "";
  document.getElementById("queueMeta").textContent = "";
  document.getElementById("durationChip").textContent = "";
  document.getElementById("viewerChip").textContent = "";
  document.getElementById("liveChip")?.classList.add("hidden");
  setOpsEmptyVisible(true);
  syncEmptyPanels(false);
  updateTopbarActions(false);
}

/**
 * Actividade para a vendedora: só resultados operacionais confirmados (ok=true).
 * Falhas técnicas (live_ended, retries, parse, …) ficam no Modo Técnico / journal.
 */
function humanActivity(entry, { includeTech = false } = {}) {
  const buyer = entry.buyer || "Comprador";
  const ref = (entry.ref_out || entry.ref_in || entry.slot_in || "").toString();
  const qty = entry.qty_out ?? entry.qty_in;
  const raw = entry.raw ? String(entry.raw).slice(0, 120) : "";
  const intent = String(entry.intent || "").toLowerCase();
  const action = String(entry.action || "").toLowerCase();
  const err = entry.error ? String(entry.error) : "";

  if (entry.ok === false) {
    if (!includeTech) return null;
    return {
      kind: "err",
      title: `Falha técnica · ${buyer}${err ? ` · ${err}` : ""}`,
      detail: raw || err || "Rejeitado",
      t: entry.t,
      isReserve: intent === "reserve",
      tech: true,
    };
  }

  if (intent === "chat" || intent === "ambiguous") return null;
  if (action === "skipped_chat") return null;

  if (intent === "cancel" || /cancel/.test(action)) {
    return {
      kind: "warn",
      title: `${buyer} cancelou${ref ? ` · ${ref}` : ""}`,
      detail: raw || (qty != null ? `Qtd: ${qty}` : ""),
      t: entry.t,
      isReserve: false,
      matchKey: window.FleaberStudioActivity?.journalMatchKey?.(entry) || null,
    };
  }
  if (intent === "reserve" || /created|superseded|updated/.test(action)) {
    const qtyBit = qty != null ? ` ×${qty}` : "";
    const refBit = ref ? ` ${ref}` : "";
    const verb = action === "superseded" ? "Actualizou reserva" : "Reservou";
    return {
      kind: "ok",
      title: `${buyer} · ${verb}${refBit}${qtyBit}`,
      detail: raw,
      t: entry.t,
      isReserve: true,
    };
  }
  // Outros ok=true com acção confirmada (ex. pagamento futuro)
  if (entry.ok === true && action) {
    return {
      kind: "ok",
      title: `${buyer} · ${action}`,
      detail: raw,
      t: entry.t,
      isReserve: false,
    };
  }
  return null;
}

function humanTechJournal(entry) {
  return humanActivity(entry, { includeTech: true });
}

function renderFeedList(el, items, emptyText) {
  if (!el) return;
  if (!items.length) {
    el.innerHTML = `<li class="empty">${escapeHtml(emptyText)}</li>`;
    return;
  }
  el.innerHTML = items
    .map(
      (u) =>
        `<li class="feed-item ${u.kind}">` +
        `<div class="feed-time">${escapeHtml(formatTimeShort(u.t))}</div>` +
        `<div class="feed-body"><p class="feed-title">${escapeHtml(u.title)}</p>` +
        (u.detail ? `<p class="feed-detail">${escapeHtml(u.detail)}</p>` : "") +
        `</div>` +
        (u.actionsHtml || "<div></div>") +
        `</li>`,
    )
    .join("");
}

async function refreshSellerSessionUi() {
  const S = window.FleaberStudioSeller;
  if (!S) return;
  sellerSession = await S.getSession();
  const gate = document.getElementById("btnShowSellerLogin");
  const form = document.getElementById("sellerLoginForm");
  const bar = document.getElementById("sellerLoggedBar");
  const label = document.getElementById("sellerLoggedLabel");
  const chip = document.getElementById("sellerChip");
  if (sellerSession?.accessToken) {
    sellerLoginFormOpen = false;
    gate?.classList.add("hidden");
    form?.classList.add("hidden");
    bar?.classList.remove("hidden");
    const display = sellerDisplayName();
    const owns = sellerSessionOwnsLive();
    if (label) {
      label.textContent =
        owns === false ? `${display} · ≠ directo` : display;
    }
    if (chip) {
      chip.textContent =
        owns === false
          ? `· ${display} (conta ≠ dono do directo)`
          : `· ${display}`;
    }
  } else {
    bar?.classList.add("hidden");
    sellerProfile = null;
    if (sellerLoginFormOpen) {
      // Polling/refresh NÃO pode fechar o formulário nem apagar texto.
      gate?.classList.add("hidden");
      form?.classList.remove("hidden");
    } else {
      form?.classList.add("hidden");
      gate?.classList.remove("hidden");
    }
    if (chip) chip.textContent = "";
    sellerQueueRows = [];
  }
}

async function ensureSellerProfile(cfg) {
  if (!sellerSession?.accessToken || !window.FleaberStudioHub?.fetchSellerProfile) {
    return;
  }
  // Perfil da CONTA com que entraste (não o dono Hub do directo — evita
  // mostrar «Vendora Mux C» com JWT de outra conta → fila not_allowed).
  const sellerId = sellerSession.userId || null;
  const handle =
    cfg?.sellerHandle ||
    sellerProfile?.handle ||
    null;
  if (
    sellerProfile &&
    ((sellerId && sellerProfile.id === sellerId) ||
      (handle && sellerProfile.handle === handle && sellerProfile.id === sellerId))
  ) {
    return;
  }
  try {
    sellerProfile = await window.FleaberStudioHub.fetchSellerProfile({
      sellerId,
      sellerHandle: handle,
    });
  } catch (_) {
    /* ignore */
  }
}

function availableForItem(liveItemId) {
  const p = (hubBundle?.products || []).find(
    (x) => String(x.liveItemId) === String(liveItemId),
  );
  return p?.availableQty ?? null;
}

function queueRowView(row, opts = {}) {
  const S = window.FleaberStudioSeller;
  const Act = window.FleaberStudioActivity;
  const readOnly = !!opts.readOnly;
  const buyer =
    row.external_display_name ||
    row.buyer_display_name ||
    row.display_name ||
    "Comprador";
  const qty = row.requested_qty ?? row.quantity ?? 1;
  const ref = row.ref_code || row.resolved_ref_slug || "";
  const refShow = String(ref || "").replace(/^#/, "").toUpperCase();
  const state = Act?.commercialState?.(row);
  const avail = availableForItem(row.live_item_id);
  const waitlist = S?.isWaitlist(row, avail);
  const needsReview = S?.isPsNeedsReview(row);
  const canPending = S?.canActPending(row);
  const id = row.id;

  let kind = state?.kind || "ok";
  if (needsReview) kind = "warn";
  if (waitlist && canPending) kind = "warn";

  const statusLabel = state?.label || String(row.status || "");
  const bits = [
    refShow ? refShow : null,
    `×${qty}`,
    statusLabel,
    waitlist && canPending ? "lista de espera" : null,
    needsReview ? "rever PS" : null,
  ].filter(Boolean);

  let actionsHtml = "<div></div>";
  if (!readOnly) {
    if (needsReview && id) {
      actionsHtml =
        `<div class="feed-actions">` +
        `<button type="button" class="btn btn-ok btn-sm" data-q-act="ps-confirm" data-id="${escapeHtml(id)}">Confirmar</button>` +
        `<button type="button" class="btn btn-ghost btn-sm" data-q-act="ps-reject" data-id="${escapeHtml(id)}">Ignorar</button>` +
        `</div>`;
    } else if (canPending && id) {
      const promoteLabel = waitlist ? "Promover" : "Aceitar";
      actionsHtml =
        `<div class="feed-actions">` +
        `<button type="button" class="btn btn-ok btn-sm" data-q-act="accept" data-id="${escapeHtml(id)}">${promoteLabel}</button>` +
        `<button type="button" class="btn btn-warn btn-sm" data-q-act="reject" data-id="${escapeHtml(id)}">Rejeitar</button>` +
        `</div>`;
    }
  }

  return {
    kind,
    title: `${buyer}`,
    detail: bits.join(" · "),
    t: row.created_at || row.updated_at,
    actionsHtml,
  };
}

function renderSellerQueue() {
  const el = document.getElementById("sellerQueueFeed");
  const elReservas = document.getElementById("reservasFeed");
  const hint = document.getElementById("queueHint");
  const hintDup = document.getElementById("queueHintDup");
  const meta = document.getElementById("queueMeta");
  if (!sellerSession?.accessToken) {
    const emptyLogin = "Entra na conta para ver a fila com nomes.";
    renderFeedList(el, [], emptyLogin);
    if (elReservas) renderFeedList(elReservas, [], emptyLogin);
    if (hint) {
      hint.textContent = "Com a conta ligada podes aceitar ou rejeitar pedidos.";
    }
    if (hintDup) {
      hintDup.textContent = "Entra na conta (canto esquerdo) para Aceitar / Rejeitar.";
    }
    if (meta) meta.textContent = "Conta não ligada";
    return;
  }
  const actionable = sellerQueueRows.filter((r) => {
    const S = window.FleaberStudioSeller;
    return S?.isPsNeedsReview(r) || S?.canActPending(r);
  });
  // Mostrar todos os pedidos (não só acionáveis) — cancelados também visíveis.
  const ordered = [...sellerQueueRows].sort((a, b) => {
    const aAct =
      window.FleaberStudioSeller?.canActPending?.(a) ||
      window.FleaberStudioSeller?.isPsNeedsReview?.(a)
        ? 0
        : 1;
    const bAct =
      window.FleaberStudioSeller?.canActPending?.(b) ||
      window.FleaberStudioSeller?.isPsNeedsReview?.(b)
        ? 0
        : 1;
    if (aAct !== bAct) return aAct - bAct;
    return (
      (Date.parse(b.updated_at || b.created_at) || 0) -
      (Date.parse(a.updated_at || a.created_at) || 0)
    );
  });
  const views = ordered.slice(0, 40).map((r) => queueRowView(r));
  const emptyMsg = "Fila vazia — ainda sem pedidos neste directo.";
  renderFeedList(el, views, emptyMsg);
  // Aba Reservas = mesma fila com Aceitar (não o journal Face)
  if (elReservas) {
    renderFeedList(elReservas, views, emptyMsg);
    elReservas.querySelectorAll("[data-q-act]").forEach((btn) => {
      btn.addEventListener("click", () => {
        void handleQueueAction(
          btn.getAttribute("data-q-act"),
          btn.getAttribute("data-id"),
        );
      });
    });
  }
  const hintText = actionable.length
    ? `${actionable.length} a precisar de acção · ${sellerQueueRows.length} no total`
    : `${sellerQueueRows.length} pedido(s) · nada por aceitar`;
  if (hint) hint.textContent = hintText;
  if (hintDup) hintDup.textContent = hintText;
  if (meta) meta.textContent = sellerQueueRows.length ? `${sellerQueueRows.length} pedidos` : "Fila";

  el?.querySelectorAll("[data-q-act]").forEach((btn) => {
    btn.addEventListener("click", () => {
      void handleQueueAction(btn.getAttribute("data-q-act"), btn.getAttribute("data-id"));
    });
  });
}

async function loadSellerQueue(liveId) {
  const S = window.FleaberStudioSeller;
  if (!S || !liveId || !sellerSession?.accessToken) {
    sellerQueueRows = [];
    renderSellerQueue();
    return;
  }
  const owns = sellerSessionOwnsLive();
  if (owns === false) {
    sellerQueueRows = [];
    const liveHandle =
      hubBundle?.hubLive?.seller_handle ||
      hubBundle?.hubLive?.seller_name ||
      "outra conta";
    const msg = `Conta do Studio ≠ dono do directo (@${String(liveHandle).replace(/^@/, "")}). Sai e entra com a conta certa para aceitar pedidos.`;
    renderFeedList(document.getElementById("sellerQueueFeed"), [], msg);
    renderFeedList(document.getElementById("reservasFeed"), [], msg);
    const hint = document.getElementById("queueHint");
    if (hint) {
      hint.textContent =
        "A fila só abre para o vendedor dono deste directo. Verifica o login no canto esquerdo.";
    }
    const hintDup = document.getElementById("queueHintDup");
    if (hintDup) hintDup.textContent = hint?.textContent || "";
    const meta = document.getElementById("queueMeta");
    if (meta) meta.textContent = "Conta desalinhada";
    return;
  }
  const out = await S.queueForLive(liveId, true);
  if (!out.ok) {
    sellerQueueRows = [];
    const err = String(out.error || "erro");
    const human =
      /not_allowed/i.test(err)
        ? "Sem permissão na fila — confirma que o login do Studio é o mesmo vendedor do directo no telemóvel."
        : `Não foi possível carregar a fila: ${err}`;
    renderFeedList(document.getElementById("sellerQueueFeed"), [], human);
    renderFeedList(document.getElementById("reservasFeed"), [], human);
    return;
  }
  sellerQueueRows = out.rows || [];
  renderSellerQueue();
  // Recalcular KPIs com contagem canónica da fila
  if (hubBundle && window.FleaberStudioHub?.computeMetrics) {
    chrome.storage.local.get(["psStepJournal"], (cfgJ) => {
      hubMetrics = window.FleaberStudioHub.computeMetrics({
        hubLive: hubBundle.hubLive,
        fomo: hubBundle.fomo,
        products: hubBundle.products || [],
        journal: cfgJ.psStepJournal,
        frozenDurationSec: null,
        queueRows: sellerQueueRows,
      });
      chrome.storage.local.get(
        ["liveId", "liveTitle", "enabled", "deviceToken", "psExtStats", "hubLiveUrl", "sellerHandle"],
        async (cfg) => {
          const faceTab = await findFacebookTab();
          renderOps({ ...cfg, psStepJournal: cfgJ.psStepJournal }, faceTab);
        },
      );
    });
  }
  // Actividade comercial reflecte a fila (pending/aceite/…), não só journal PS.
  chrome.storage.local.get(["psStepJournal"], (cfg) => {
    renderActivity(cfg.psStepJournal);
    refreshLiveChatFromStorage();
  });
  updateReservasBadge();
}

async function handleQueueAction(act, requestId) {
  const S = window.FleaberStudioSeller;
  if (!S || !requestId || queueBusy) return;
  queueBusy = true;
  setMsg(statusMsg, "A processar…");
  try {
    let res;
    if (act === "ps-confirm") res = await S.confirmPs(requestId, "confirm");
    else if (act === "ps-reject") res = await S.confirmPs(requestId, "reject");
    else if (act === "accept") res = await S.processReservation(requestId, "accept");
    else if (act === "reject") res = await S.processReservation(requestId, "reject");
    else {
      setMsg(statusMsg, "Acção desconhecida.", "err");
      return;
    }
    const payload = res?.data;
    if (!res?.ok || (payload && typeof payload === "object" && payload.ok === false)) {
      const tech =
        (payload && payload.error) || res.error || "erro";
      const mapped = sellerFriendlyError(tech);
      setMsg(statusMsg, mapped.human, "err");
      try {
        const cfgJ = await chrome.storage.local.get(["psStepJournal"]);
        const list = Array.isArray(cfgJ.psStepJournal) ? cfgJ.psStepJournal : [];
        list.push({
          t: Date.now(),
          ok: false,
          action: `queue_${act}`,
          error: mapped.tech,
          intent: "tech",
          raw: mapped.human,
        });
        await chrome.storage.local.set({ psStepJournal: list.slice(-200) });
      } catch (_) {}
    } else {
      setMsg(statusMsg, "Fila actualizada.", "ok");
    }
    const cfg = await chrome.storage.local.get(["liveId"]);
    await loadSellerQueue(cfg.liveId);
    refreshAll._lastHubAt = 0;
    await refreshAll();
  } catch (e) {
    setMsg(statusMsg, String(e.message || e), "err");
  } finally {
    queueBusy = false;
  }
}

async function findFacebookTab() {
  const tabs = await chrome.tabs.query({});
  const face = tabs.filter((t) => t.url && isFacebookUrl(t.url));
  if (!face.length) return null;
  // Preferir o separador do directo (vídeo), não o feed genérico
  const liveTab = face.find(
    (t) => /\/videos\/|\/watch\/|\/live\b|\/reel\//i.test(String(t.url || "")),
  );
  if (liveTab) return liveTab;
  const active = face.find((t) => t.active);
  if (active) return active;
  face.sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0));
  return face[0];
}

/** Evita spam de inject automático (extensão reload → script Face fica órfão). */
let _lastAutoInjectAt = 0;

async function injectIntoFaceTab(opts = {}) {
  const quiet = !!opts.quiet;
  const tab = await findFacebookTab();
  if (!tab?.id) {
    if (!quiet) {
      setMsg(
        statusMsg,
        "Abre o Facebook Live (ou simulador 127.0.0.1:8765) noutro separador.",
        "err",
      );
    }
    return false;
  }
  if (!quiet) {
    setMsg(statusMsg, "A activar acompanhamento na página Facebook…");
  }
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content_loader.js"],
    });
    if (!quiet) {
      setMsg(
        statusMsg,
        '<span class="ok">Leitura activada nesta página Face.</span>',
        "ok",
      );
    }
    setTimeout(refreshAll, 600);
    setTimeout(refreshAll, 1600);
    setTimeout(refreshAll, 3500);
    return true;
  } catch (e) {
    if (!quiet) {
      setMsg(statusMsg, `Falha a activar: ${e.message || e}`, "err");
    }
    return false;
  }
}

/**
 * Se emparelhado + leitura ON + Face aberto mas script morto/stale
 * (comum após Reload da extensão) → reinject automaticamente.
 */
async function maybeAutoInjectFace(cfg, faceTab) {
  const paired = !!(cfg?.liveId && cfg?.deviceToken);
  const enabled = !!cfg?.enabled;
  if (!paired || !enabled || !faceTab?.id) return;
  const st = cfg?.psExtStats || null;
  const age = st?.updatedAt ? Date.now() - st.updatedAt : 99999;
  const needs =
    !st?.updatedAt ||
    age > 10000 ||
    (st?.boot && !st?.scans && age > 4000) ||
    (!!st?.lastError && /extension context|context invalidated/i.test(String(st.lastError)));
  if (!needs) return;
  if (Date.now() - _lastAutoInjectAt < 12000) return;
  _lastAutoInjectAt = Date.now();
  await injectIntoFaceTab({ quiet: true });
}

/** Foca o separador Facebook existente ou abre facebook.com (vídeo continua no browser). */
async function focusFacebookTab() {
  try {
    const tab = await findFacebookTab();
    if (tab?.id) {
      await chrome.tabs.update(tab.id, { active: true });
      if (tab.windowId != null) {
        await chrome.windows.update(tab.windowId, { focused: true });
      }
      setMsg(statusMsg, "Separador Facebook em foco.", "ok");
      return;
    }
    await chrome.tabs.create({ url: "https://www.facebook.com/" });
    setMsg(
      statusMsg,
      "Abri o Facebook — entra no directo e activa a leitura.",
      "ok",
    );
  } catch (e) {
    setMsg(statusMsg, `Não foi possível abrir o Facebook: ${e.message || e}`, "err");
  }
}

function renderDiag(cfg, st) {
  const diagBox = document.getElementById("diagBox");
  if (!cfg?.liveId) {
    diagBox.innerHTML = "Diagnóstico: não emparelhado.";
    return;
  }
  if (!st || !st.updatedAt) {
    diagBox.innerHTML =
      '<span class="warn">Script ainda não activo nesta página.</span>';
    return;
  }
  const ageSec = Math.round((Date.now() - st.updatedAt) / 1000);
  const stale = ageSec > 8;
  const cls = stale ? "warn" : "ok";
  const bootOnly = st.boot && !st.scans;
  diagBox.innerHTML =
    `<span class="${cls}">Script: ${st.active ? "ON" : bootOnly ? "a arrancar" : "OFF"} · há ${ageSec}s</span><br>` +
    (st.pageUrl ? `URL: ${escapeHtml(String(st.pageUrl).slice(0, 90))}…<br>` : "") +
    `Scans: ${st.scans || 0} · blocos: ${st.blocksSeen || 0} · parse: ${st.parsed || 0} · enviados: ${st.ingested || 0}<br>` +
    `Fila: ${st.queueDepth || 0}` +
    (st.harnessWaiting ? ' · <span class="warn">à espera de Correr</span>' : "") +
    `<br>IA: usada ${st.llmUsed || 0} · falhou ${st.llmMiss || 0}` +
    (st.lastLlm ? ` · ${escapeHtml(st.lastLlm)}` : "") +
    `<br>Zonas chat: ${st.rootsFound || 0}<br>` +
    (st.lastAction ? `Última: ${escapeHtml(st.lastAction)}<br>` : "") +
    (st.lastBlock ? `Último: «${escapeHtml(st.lastBlock)}»<br>` : "") +
    (st.lastError ? `<span class="err">Erro: ${escapeHtml(st.lastError)}</span>` : "");
}

async function refreshOllamaStatus() {
  const cfg = await chrome.storage.local.get([
    "ollamaEnabled",
    "ollamaModel",
    "ollamaTier",
    "strictRefMode",
  ]);
  const strictRefEl = document.getElementById("strictRef");
  const ollamaEl = document.getElementById("ollama");
  const aiTierEl = document.getElementById("aiTier");
  const ollamaStatusEl = document.getElementById("ollamaStatus");
  strictRefEl.checked = cfg.strictRefMode !== false;
  ollamaEl.checked = !!cfg.ollamaEnabled;
  aiTierEl.value = cfg.ollamaTier || "auto";
  if (!cfg.ollamaEnabled) {
    ollamaStatusEl.innerHTML = 'IA: <span class="warn">desligada</span>';
    return;
  }
  chrome.runtime.sendMessage({ type: "ollama_ping" }, (resp) => {
    if (chrome.runtime.lastError || !resp?.ok) {
      ollamaStatusEl.innerHTML = 'IA: <span class="err">Ollama offline / CORS</span>';
      return;
    }
    const model = resolveOllamaModel(cfg.ollamaTier, cfg.ollamaModel);
    const has = (resp.models || []).some(
      (m) => m === model || m.startsWith(`${model}:`) || model.startsWith(m),
    );
    ollamaStatusEl.innerHTML = has
      ? `IA: <span class="ok">${escapeHtml(model)}</span>`
      : `IA: <span class="warn">modelo em falta</span>`;
  });
}

function productCardHtml(p) {
  const Act = window.FleaberStudioActivity;
  const ref = escapeHtml((p.refCode || "?").toString().slice(0, 8));
  const thumb = p.photoUrl
    ? `<div class="thumb has-photo" style="background-image:url('${escapeHtml(p.photoUrl)}')"></div>`
    : `<div class="thumb thumb-ph"><span>${ref}</span></div>`;
  const price =
    p.price != null ? formatEuro(p.price) : "Preço —";
  // Formato único: sempre «Disp. A / T» quando há total; saco = «No saco N»
  let stockLabel = null;
  if (p.availableQty != null) {
    const avail = Number(p.availableQty);
    const total = p.totalQty != null ? Number(p.totalQty) : null;
    stockLabel =
      total != null && Number.isFinite(total)
        ? `Disp. ${avail} / ${total}`
        : `Disp. ${avail}`;
  }
  const bagQty = Number(p.pendingBagQty ?? 0);
  const acceptedQty = Number(p.acceptedQty ?? 0);
  const reservedFallback =
    p.reservedQty != null && Number(p.reservedQty) > 0
      ? Number(p.reservedQty)
      : 0;
  const summary =
    p.commercialSummary ||
    Act?.productCommercialSummary?.(p, sellerQueueRows) ||
    null;
  const commercialLine = summary?.line
    ? `<div class="prod-state${summary.kind ? ` ${summary.kind}` : ""}">${escapeHtml(summary.line)}</div>` +
      (summary.sub
        ? `<div class="prod-state-sub">${escapeHtml(summary.sub)}</div>`
        : "")
    : "";
  const bagBit =
    bagQty > 0
      ? `No saco ${bagQty}`
      : reservedFallback > 0 && acceptedQty <= 0
        ? `No saco ${reservedFallback}`
        : null;
  const acceptedBit =
    acceptedQty > 0 ? `Reservada ${acceptedQty}` : null;
  const stats = [
    stockLabel,
    bagBit,
    acceptedBit,
    p.soldQty != null && Number(p.soldQty) > 0 ? `Vend. ${p.soldQty}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  return (
    `<div class="prod-card${p.isActive ? " active" : ""}${summary?.code === "bag" ? " in-bag" : ""}${summary?.code === "accepted" ? " reserved" : ""}${summary?.code === "sold" ? " sold" : ""}">` +
    (p.isActive ? '<span class="tag">A apresentar</span>' : "") +
    thumb +
    `<div class="name">${escapeHtml(p.title || p.refCode || "Artigo")}</div>` +
    `<div class="price">${escapeHtml(price)}</div>` +
    commercialLine +
    (stats ? `<div class="stats">${escapeHtml(stats)}</div>` : "") +
    `</div>`
  );
}

function setMuxEmpty(htmlOrText, isHtml = false) {
  const empty = document.getElementById("muxEmpty");
  if (!empty) return;
  empty.classList.remove("hidden");
  if (isHtml) {
    empty.innerHTML = htmlOrText;
  } else {
    empty.innerHTML =
      `<div class="empty-illu" aria-hidden="true"></div><strong>Sem preview de momento</strong><span>${escapeHtml(htmlOrText)}</span>`;
  }
}

function sellerFriendlyError(codeOrMsg) {
  const raw = String(codeOrMsg || "").trim();
  const key = raw.split(/[\s:|]/)[0].toLowerCase();
  const map = {
    live_item_qty_below_reservations:
      "Não foi possível aceitar a reserva porque já não existe stock suficiente.",
    qty_exceeds_stock:
      "Não foi possível aceitar a reserva porque já não existe stock suficiente.",
    no_stock:
      "Não foi possível aceitar a reserva porque já não existe stock suficiente.",
    live_ended:
      "Este directo já terminou — não dá para aceitar novas reservas Face.",
    item_sold: "Este artigo já está marcado como vendido.",
    not_allowed: "Não tens permissão para esta acção.",
    request_not_found: "Pedido não encontrado — actualiza a fila.",
    request_state_conflict: "O estado deste pedido mudou. Actualiza a fila.",
    seller_not_signed_in: "Entra na conta vendedora para gerir a fila.",
    invalid_action: "Acção inválida.",
  };
  if (map[key]) return { human: map[key], tech: raw };
  if (/live_item_qty_below|qty_exceeds|no_stock/i.test(raw)) {
    return {
      human:
        "Não foi possível aceitar a reserva porque já não existe stock suficiente.",
      tech: raw,
    };
  }
  return {
    human: "Não foi possível concluir a acção. Tenta outra vez.",
    tech: raw || "erro",
  };
}

function applyMuxAspectFromVideo(video, { forceLivePortrait = false } = {}) {
  const wrap = document.getElementById("muxWrap");
  if (!wrap || !video) return;
  // LIVE: manter 9:16 do CSS. metadata/HLS reporta landscape e
  // substituía o vertical correcto ~1s depois (inline aspectRatio).
  if (forceLivePortrait || lastMuxIsLive) {
    wrap.style.aspectRatio = "";
    wrap.dataset.aspect = "portrait";
    wrap.classList.add("is-live-portrait");
    return;
  }
  const w = video.videoWidth || 0;
  const h = video.videoHeight || 0;
  if (w < 2 || h < 2) return;
  wrap.style.aspectRatio = `${w} / ${h}`;
  wrap.dataset.aspect = w >= h ? "landscape" : "portrait";
  wrap.classList.remove("is-live-portrait");
}

function stopLiveEdgeKeepAlive() {
  if (liveEdgeKeepAliveTimer) {
    clearInterval(liveEdgeKeepAliveTimer);
    liveEdgeKeepAliveTimer = null;
  }
}

function setMuxLivePill(on) {
  const pill = document.getElementById("muxLivePill");
  const chrome = document.getElementById("muxLiveChrome");
  const wrap = document.getElementById("muxWrap");
  const video = document.getElementById("muxVideo");
  if (pill) {
    pill.classList.toggle("hidden", !on);
    pill.setAttribute("aria-hidden", on ? "false" : "true");
  }
  if (chrome) chrome.classList.toggle("hidden", !on);
  if (wrap) wrap.classList.toggle("is-live", !!on);
  // LIVE = monitor (sem seekbar/duração VOD). VOD/replay = controls nativos.
  if (video) {
    if (on) video.removeAttribute("controls");
    else video.setAttribute("controls", "");
  }
}

function wireMuxLiveChromeOnce() {
  if (wireMuxLiveChromeOnce._done) return;
  wireMuxLiveChromeOnce._done = true;
  const video = document.getElementById("muxVideo");
  const playBtn = document.getElementById("muxBtnPlay");
  const muteBtn = document.getElementById("muxBtnMute");
  const liveBtn = document.getElementById("muxBtnLive");
  const fsBtn = document.getElementById("muxBtnFs");
  playBtn?.addEventListener("click", () => {
    if (!video) return;
    if (video.paused) video.play().catch(() => {});
    else video.pause();
  });
  muteBtn?.addEventListener("click", () => {
    if (!video) return;
    video.muted = !video.muted;
    if (muteBtn) muteBtn.textContent = video.muted ? "🔇" : "🔊";
  });
  liveBtn?.addEventListener("click", () => {
    seekToLiveEdge();
    video?.play().catch(() => {});
  });
  fsBtn?.addEventListener("click", () => {
    const wrap = document.getElementById("muxWrap");
    if (!wrap) return;
    if (document.fullscreenElement) {
      document.exitFullscreen?.().catch(() => {});
    } else {
      wrap.requestFullscreen?.().catch(() => {});
    }
  });
  video?.addEventListener("play", () => {
    if (playBtn) playBtn.textContent = "❚❚";
  });
  video?.addEventListener("pause", () => {
    if (playBtn) playBtn.textContent = "▶";
  });
}

function seekToLiveEdge() {
  const video = document.getElementById("muxVideo");
  if (!video) return;
  try {
    const edge =
      hlsPlayer && hlsPlayer.liveSyncPosition != null
        ? hlsPlayer.liveSyncPosition
        : null;
    if (edge != null && Number.isFinite(edge)) {
      video.currentTime = Math.max(0, edge);
      return;
    }
    if (video.seekable && video.seekable.length > 0) {
      const end = video.seekable.end(video.seekable.length - 1);
      if (Number.isFinite(end) && end > 0) {
        video.currentTime = Math.max(0, end - 1);
      }
    }
  } catch (_) {}
}

/**
 * Mantém o player no live edge. Sem UI de duração VOD (0:12/0:12).
 */
function startLiveEdgeKeepAlive() {
  stopLiveEdgeKeepAlive();
  liveEdgeKeepAliveTimer = setInterval(() => {
    if (!lastMuxIsLive) return;
    const video = document.getElementById("muxVideo");
    if (!video || video.paused) return;
    seekToLiveEdge();
  }, 4000);
}

function attachMux(playbackUrl, isLive) {
  const video = document.getElementById("muxVideo");
  const empty = document.getElementById("muxEmpty");
  const muxMeta = document.getElementById("muxMeta");
  wireMuxLiveChromeOnce();
  stopLiveEdgeKeepAlive();
  lastMuxIsLive = !!isLive;
  setMuxLivePill(false);
  if (!playbackUrl) {
    if (hlsPlayer) {
      try {
        hlsPlayer.destroy();
      } catch (_) {}
      hlsPlayer = null;
    }
    video.removeAttribute("src");
    video.load?.();
    video.classList.remove("visible");
    const wrap = document.getElementById("muxWrap");
    if (wrap) {
      wrap.style.aspectRatio = "";
      delete wrap.dataset.aspect;
      wrap.classList.remove("is-live-portrait");
    }
    document.getElementById("muxLiveChrome")?.classList.add("hidden");
    setMuxEmpty("Quando o directo estiver a transmitir, o vídeo aparece aqui.");
    lastMuxUrl = "";
    return;
  }
  if (playbackUrl === lastMuxUrl && video.classList.contains("visible")) {
    if (isLive) {
      setMuxLivePill(true);
      startLiveEdgeKeepAlive();
    }
    return;
  }
  lastMuxUrl = playbackUrl;
  empty.classList.add("hidden");
  video.classList.add("visible");

  if (hlsPlayer) {
    try {
      hlsPlayer.destroy();
    } catch (_) {}
    hlsPlayer = null;
  }

  const onFatal = (detail) => {
    console.warn("[Seller Studio] mux playback", detail, playbackUrl);
    lastMuxUrl = "";
    lastMuxIsLive = false;
    stopLiveEdgeKeepAlive();
    setMuxLivePill(false);
    document.getElementById("muxLiveChrome")?.classList.add("hidden");
    video.classList.remove("visible");
    if (muxMeta) muxMeta.textContent = "Sem vídeo";
    setMuxEmpty(
      "Não foi possível reproduzir o vídeo desta live. Verifica a transmissão e Actualizar (Modo Técnico tem o detalhe).",
    );
    try {
      chrome.storage.local.get(["psStepJournal"], (cfg) => {
        const list = Array.isArray(cfg.psStepJournal) ? cfg.psStepJournal : [];
        list.push({
          t: Date.now(),
          ok: false,
          action: "mux_playback_error",
          error: String(detail || "fatal"),
          raw: String(playbackUrl || "").slice(0, 160),
          intent: "tech",
        });
        chrome.storage.local.set({ psStepJournal: list.slice(-200) });
      });
    } catch (_) {}
  };

  video.onloadedmetadata = () => {
    applyMuxAspectFromVideo(video, { forceLivePortrait: !!isLive });
  };

  if (video.canPlayType("application/vnd.apple.mpegurl")) {
    video.src = playbackUrl;
    video.play().catch(() => {});
    if (isLive) {
      setMuxLivePill(true);
      if (muxMeta) muxMeta.textContent = "Monitor em directo · sem barra de duração";
      video.addEventListener("loadedmetadata", seekToLiveEdge, { once: true });
      startLiveEdgeKeepAlive();
    } else if (muxMeta) {
      muxMeta.textContent = "Gravação (VOD)";
    }
    return;
  }
  if (window.Hls && window.Hls.isSupported()) {
    hlsPlayer = new window.Hls({
      enableWorker: false,
      lowLatencyMode: !!isLive,
      liveDurationInfinity: !!isLive,
      liveSyncDurationCount: isLive ? 3 : undefined,
      liveMaxLatencyDurationCount: isLive ? 10 : undefined,
      xhrSetup(xhr) {
        try {
          xhr.withCredentials = false;
        } catch (_) {}
      },
    });
    hlsPlayer.loadSource(playbackUrl);
    hlsPlayer.attachMedia(video);
    hlsPlayer.on(window.Hls.Events.MANIFEST_PARSED, () => {
      applyMuxAspectFromVideo(video, { forceLivePortrait: !!isLive });
      if (isLive) seekToLiveEdge();
      video.play().catch(() => {});
      if (isLive) {
        setMuxLivePill(true);
        if (muxMeta) muxMeta.textContent = "Monitor em directo · sem barra de duração";
        startLiveEdgeKeepAlive();
      } else if (muxMeta) {
        muxMeta.textContent = "Gravação (VOD)";
      }
    });
    hlsPlayer.on(window.Hls.Events.ERROR, (_ev, data) => {
      if (data?.fatal) {
        const detail = [data.type, data.details, data.response?.code]
          .filter(Boolean)
          .join(":");
        try {
          hlsPlayer.destroy();
        } catch (_) {}
        hlsPlayer = null;
        onFatal(detail || "fatal");
      }
    });
    return;
  }
  onFatal("hls_unsupported");
}

function renderHubPanels(cfg) {
  if (!cfg?.liveId) {
    clearOpsDashboardUi();
    renderSellerQueue();
    return;
  }
  setOpsEmptyVisible(false);

  const products = hubBundle?.products || [];
  const metrics = hubMetrics;
  const hubLive = hubBundle?.hubLive;

  document.getElementById("prodStrip").innerHTML = products.length
    ? products.slice(0, 12).map(productCardHtml).join("")
    : '<div class="empty">Ainda sem produtos neste directo.</div>';
  document.getElementById("prodGrid").innerHTML = products.length
    ? products.map(productCardHtml).join("")
    : '<div class="empty">Ainda sem produtos neste directo.</div>';
  document.getElementById("prodStripMeta").textContent = products.length
    ? `${products.length} artigos`
    : "";

  // Fila agregada
  const fila = products
    .filter((p) => (p.pendingQueue || 0) > 0)
    .map((p) => ({
      kind: "warn",
      title: `${p.title || p.refCode || "Artigo"} · ${p.pendingQueue} na fila`,
      detail: p.refCode ? `Ref ${p.refCode}` : "Na fila a aguardar",
      t: null,
    }));
  renderFeedList(
    document.getElementById("filaFeed"),
    fila,
    "Ninguém na fila de momento.",
  );

  // Pagamentos agregados
  const pay = document.getElementById("payState");
  if (metrics && (metrics.pendingBagTotal != null || metrics.acceptedPayTotal != null)) {
    pay.innerHTML =
      `<div class="mini-chip"><div class="k">Unid. no saco</div><div class="v">${metrics.pendingBagTotal ?? "—"}</div></div>` +
      `<div class="mini-chip"><div class="k">Aceite a pagar</div><div class="v">${metrics.acceptedPayTotal ?? "—"}</div></div>` +
      `<div class="mini-chip"><div class="k">Na fila</div><div class="v">${metrics.pendingQueueTotal}</div></div>` +
      `<div class="mini-chip"><div class="k">Stock baixo</div><div class="v">${metrics.lowStockCount}</div></div>`;
  } else {
    pay.innerHTML = "";
  }

  // Mini Fleaber — só estado (KPIs comerciais já estão em opsKpiRow)
  const mini = document.getElementById("fleaberMini");
  const stHub = hubLive?.status || hubBundle?.fomo?.live_status || "—";
  const online = window.FleaberStudioHub?.isHubLiveActive
    ? window.FleaberStudioHub.isHubLiveActive(hubLive)
    : !!(hubLive?.is_active || String(stHub).toLowerCase() === "live");
  if (mini) {
    mini.innerHTML = online
      ? ""
      : `<div class="mini-chip"><div class="k">Estado</div><div class="v">${escapeHtml(humanLiveStatus(stHub))}</div></div>`;
    mini.classList.toggle("hidden", !cfg?.liveId || online);
  }

  setLed(document.getElementById("ledFleaber"), online ? "on" : hubLive ? "warn" : "off");
  document.getElementById("valFleaber").textContent = online
    ? "Em directo"
    : hubLive
      ? humanLiveStatus(stHub)
      : "—";
  document.getElementById("hintFleaber").textContent = hubLive?.seller_handle
    ? `@${hubLive.seller_handle}`
    : cfg.hubLiveUrl
      ? "Directo ligado"
      : "Após emparelhar";

  setLed(
    document.getElementById("footFleaber"),
    online ? "on" : hubLive ? "warn" : "off",
  );

  // Mux
  const pb = hubBundle?.playback;
  const muxMeta = document.getElementById("muxMeta");
  if (muxMeta) {
    if (!pb?.ok) {
      muxMeta.textContent = pb?.error ? "Sem vídeo" : "";
    } else if (pb.isLive) {
      muxMeta.textContent = "Monitor em directo · sem barra de duração";
    } else {
      muxMeta.textContent = "Gravação (VOD)";
    }
  }
  attachMux(pb?.playbackUrl || "", !!pb?.isLive);

  // Produto actual (overlay)
  const ap = document.getElementById("activeProductCard");
  const active = products.find((p) => p.isActive) || null;
  if (ap) {
    if (active) {
      ap.classList.remove("hidden");
      const ref = escapeHtml((active.refCode || "?").toString().slice(0, 6));
      const thumb = active.photoUrl
        ? `<div class="ap-thumb has-photo" style="background-image:url('${escapeHtml(active.photoUrl)}')"></div>`
        : `<div class="ap-thumb">${ref}</div>`;
      ap.innerHTML =
        thumb +
        `<div class="ap-body"><div class="ap-name">${escapeHtml(active.title || active.refCode || "Artigo")}</div>` +
        `<div class="ap-price">${active.price != null ? escapeHtml(formatEuro(active.price)) : "—"}</div></div>` +
        `<span class="ap-tag">A apresentar</span>`;
    } else {
      ap.classList.add("hidden");
      ap.innerHTML = "";
    }
  }

  // KPIs operacionais (só reais)
  const opsKpi = document.getElementById("opsKpiRow");
  if (opsKpi && metrics) {
    const cells = [];
    function cell(label, value) {
      cells.push(
        `<div class="kpi"><div class="k">${escapeHtml(label)}</div><div class="v">${escapeHtml(String(value))}</div></div>`,
      );
    }
    cell("Espectadores", metrics.viewersFleaber != null ? metrics.viewersFleaber : "—");
    cell("Pedidos Face", metrics.fbReservesOk);
    cell(
      "Unid. no saco",
      metrics.pendingBagTotal != null ? metrics.pendingBagTotal : "—",
    );
    cell("Fila", metrics.pendingQueueTotal);
    cell("Vendidos", metrics.soldTotal != null ? metrics.soldTotal : "—");
    cell("GMV", metrics.gmvEur != null ? formatEuro(metrics.gmvEur) : "—");
    opsKpi.innerHTML = cells.join("");
  } else if (opsKpi) {
    opsKpi.innerHTML = "";
  }

  // Análises compactas (direita)
  const opsAn = document.getElementById("opsAnalytics");
  if (opsAn && metrics) {
    const cells = [];
    function cell(label, value) {
      cells.push(
        `<div class="kpi"><div class="k">${escapeHtml(label)}</div><div class="v">${escapeHtml(String(value))}</div></div>`,
      );
    }
    cell("Produtos", metrics.productsCount);
    cell("Stock baixo", metrics.lowStockCount);
    cell(
      "Unid. no saco",
      metrics.pendingBagTotal != null ? metrics.pendingBagTotal : "—",
    );
    cell("Aceite a pagar", metrics.acceptedPayTotal != null ? metrics.acceptedPayTotal : "—");
    opsAn.innerHTML = cells.join("");
  }

  // KPIs full panel (Análises)
  const kpi = document.getElementById("kpiRow");
  const chips = [];
  function addKpi(label, value, note) {
    chips.push(
      `<div class="kpi"><div class="k">${escapeHtml(label)}</div><div class="v">${escapeHtml(String(value))}</div>${note ? `<div class="s">${escapeHtml(note)}</div>` : ""}</div>`,
    );
  }
  if (metrics) {
    if (metrics.viewersFleaber != null) addKpi("Espectadores", metrics.viewersFleaber);
    if (metrics.durationSec != null) addKpi("Duração", formatDuration(metrics.durationSec));
    if (metrics.productsCount) addKpi("Produtos", metrics.productsCount);
    if (metrics.pendingQueueTotal > 0) addKpi("Na fila", metrics.pendingQueueTotal);
    // Pedidos = linhas Face; unidades = soma de qtds (não duplicar com «Reservas»)
    if (metrics.fbReservesOk > 0) {
      addKpi("Pedidos Face", metrics.fbReservesOk, "linhas / pedidos");
    }
    if (metrics.pendingBagTotal != null) {
      addKpi("Unidades no saco", metrics.pendingBagTotal, "soma das qtds");
    }
    if (metrics.acceptedPayTotal != null) {
      addKpi("Aceite a pagar", metrics.acceptedPayTotal, "unidades");
    }
    if (metrics.soldTotal != null) addKpi("Vendidos", metrics.soldTotal);
    if (metrics.gmvEur != null) addKpi("Vendas (€)", formatEuro(metrics.gmvEur));
    if (metrics.lowStockCount > 0) addKpi("Stock baixo", metrics.lowStockCount);
  }
  if (kpi) {
    kpi.innerHTML = chips.length
      ? chips.join("")
      : '<div class="empty">Ainda sem números para este directo.</div>';
  }

  const kpiSources = document.getElementById("kpiSources");
  const kpiFuture = document.getElementById("kpiFuture");
  if (kpiSources) {
    kpiSources.textContent = "";
    kpiSources.classList.add("hidden");
  }
  if (kpiFuture) {
    kpiFuture.textContent = "";
    kpiFuture.classList.add("hidden");
  }

  // Hub link — sempre a partir do handle canónico da live (não reutilizar URL stale).
  const handleForHub =
    hubLive?.seller_handle || cfg.sellerHandle || null;
  const hubUrl =
    window.FleaberStudioHub?.buildHubLiveWebUrl && handleForHub && cfg.liveId
      ? window.FleaberStudioHub.buildHubLiveWebUrl(
          handleForHub,
          cfg.liveId,
          HUB_WEB_ORIGIN,
        )
      : "";
  const btnHub = document.getElementById("btnOpenHub");
  if (hubUrl) {
    btnHub.href = hubUrl;
    btnHub.classList.remove("hidden");
    if (hubUrl !== cfg.hubLiveUrl) {
      void chrome.storage.local.set({
        hubLiveUrl: hubUrl,
        sellerHandle: handleForHub,
      });
      cfg.hubLiveUrl = hubUrl;
      cfg.sellerHandle = handleForHub;
    }
  } else {
    btnHub.classList.add("hidden");
  }

  if (metrics?.viewersFleaber != null) {
    document.getElementById("viewerChip").textContent =
      `· ${metrics.viewersFleaber} a ver`;
  } else {
    document.getElementById("viewerChip").textContent = "";
  }
  if (metrics?.durationSec != null) {
    document.getElementById("durationChip").textContent =
      `· ${formatDuration(metrics.durationSec)}`;
  } else {
    document.getElementById("durationChip").textContent = "";
  }
}

function renderAlerts(state) {
  const box = document.getElementById("alertsList");
  const alerts = [];
  const { paired, enabled, st, faceTab, metrics, hubLive } = state;

  if (!paired) {
    alerts.push({
      level: "info",
      text: "Ainda não emparelhado. Usa o código de 6 dígitos do Studio no telemóvel.",
    });
  } else if (!faceTab) {
    alerts.push({
      level: "warn",
      text: "Não há separador Facebook aberto. Abre o directo no browser.",
    });
  } else if (!st?.updatedAt || Date.now() - (st?.updatedAt || 0) > 8000) {
    alerts.push({
      level: "warn",
      text: "Leitura Face parada. Clica «Activar leitura» (ou actualiza a página do directo no Facebook).",
    });
  }

  if (paired && !enabled) {
    alerts.push({ level: "warn", text: "Leitura PS em pausa." });
  }
  // Só alertas operacionais — não cada comentário rejeitado.
  const lastErr = String(st?.lastError || "");
  if (/live_ended/i.test(lastErr)) {
    alerts.push({
      level: "warn",
      text: "O directo Fleaber terminou — novas reservas Face não são aceites até emparelhares uma live activa.",
    });
  } else if (/invalid_token|missing_device_token/i.test(lastErr)) {
    alerts.push({
      level: "err",
      text: "Emparelhamento inválido ou expirado. Desemparelha e volta a emparelhar.",
    });
  } else if (lastErr && !/item_not_found|live_item_not_available/i.test(lastErr)) {
    // Erros transitórios / canal: um aviso agregado, sem spam por comentário
    if (/timeout|546|502|503|504|429|channel|WORKER|aborted/i.test(lastErr)) {
      alerts.push({
        level: "warn",
        text: "Ligação à Fleaber instável de momento — a leitura vai tentar de novo.",
      });
    }
  }
  if (paired && hubLive && !hubLive.is_active && String(hubLive.status).toLowerCase() === "ended") {
    if (!alerts.some((a) => /terminou/.test(a.text))) {
      alerts.push({
        level: "warn",
        text: "Este directo já terminou. Novas reservas do Facebook não são aceites.",
      });
    }
  }
  if (metrics?.pendingQueueTotal > 0 && !sellerSession?.accessToken) {
    alerts.push({
      level: "warn",
      text: `${metrics.pendingQueueTotal} na fila. Entra na conta para gerir os pedidos.`,
    });
  } else if (metrics?.pendingQueueTotal > 0) {
    alerts.push({
      level: "warn",
      text: `${metrics.pendingQueueTotal} pessoa(s) na fila.`,
    });
  }
  const pendingActs = sellerQueueRows.filter((r) => {
    const S = window.FleaberStudioSeller;
    return S?.isPsNeedsReview(r) || S?.canActPending(r);
  }).length;
  if (pendingActs > 0) {
    alerts.push({
      level: "warn",
      text: `${pendingActs} reserva(s) a precisar de confirmação / aceitação.`,
    });
  }
  if (metrics?.lowStockCount > 0) {
    alerts.push({
      level: "warn",
      text: `${metrics.lowStockCount} artigo(s) com stock baixo (≤1).`,
    });
  }
  if (metrics?.acceptedPayTotal > 0) {
    alerts.push({
      level: "info",
      text: `${metrics.acceptedPayTotal} unidade(s) aceites à espera de pagamento.`,
    });
  }
  if (paired && hubLive && !hubLive.is_active && String(hubLive.status).toLowerCase() !== "live") {
    alerts.push({
      level: "info",
      text: `Estado do directo: ${humanLiveStatus(hubLive.status)}.`,
    });
  }

  if (
    paired &&
    enabled &&
    faceTab &&
    st?.updatedAt &&
    Date.now() - st.updatedAt <= 8000 &&
    !st.lastError
  ) {
    alerts.push({
      level: "ok",
      text: "Tudo a funcionar — a acompanhar o Facebook.",
    });
  }

  box.innerHTML = alerts.length
    ? alerts
        .map(
          (a) =>
            `<div class="alert ${a.level}"><span class="led"></span><div>${escapeHtml(a.text)}</div></div>`,
        )
        .join("")
    : '<div class="empty">Sem alertas.</div>';
}

function renderLiveChat(journal, transcript) {
  const el = document.getElementById("liveChatFeed");
  const meta = document.getElementById("liveChatMeta");
  if (!el) return;
  const Chat = window.FleaberStudioChat;
  const hubMsgs = hubBundle?.liveMessages || [];
  const items = Chat?.buildUnifiedChat
    ? Chat.buildUnifiedChat({
        hubMessages: hubMsgs,
        journal,
        transcript,
        limit: 80,
      })
    : [];

  if (!items.length) {
    el.innerHTML =
      '<li class="empty">Ainda sem reservas Face. Com leitura activa, pedidos de reserva/cancelamento aparecem aqui.</li>';
    if (meta) meta.textContent = "vazio";
    return;
  }

  const stickBottom =
    el.scrollHeight - el.scrollTop - el.clientHeight < 48 ||
    el.dataset.stick !== "0";

  el.innerHTML = items
    .map((m) => {
      const origin = m.origin === "facebook" ? "fb" : "fleaber";
      const badge = origin === "fb" ? "FB" : "F";
      const titleOrigin = origin === "fb" ? "Facebook" : "Fleaber";
      return (
        `<li class="chat-msg" title="${escapeHtml(titleOrigin)}">` +
        `<span class="chat-origin ${origin}" aria-label="${escapeHtml(titleOrigin)}">${badge}</span>` +
        `<div class="chat-body">` +
        `<div class="chat-name">${escapeHtml(m.name || "Utilizador")}</div>` +
        `<p class="chat-text">${escapeHtml(m.body)}</p>` +
        `</div>` +
        `<div class="chat-time">${escapeHtml(formatTimeShort(m.t))}</div>` +
        `</li>`
      );
    })
    .join("");

  const fbN = items.filter((m) => m.origin === "facebook").length;
  const flN = items.filter((m) => m.origin !== "facebook").length;
  if (meta) meta.textContent = `${items.length} · FB ${fbN} · F ${flN}`;

  // Snapshot DISPLAYED no Modo Técnico (não persiste — evita encher o TRACE)
  window.__psChatDisplayedSnapshot = items
    .filter((m) => m.origin === "facebook")
    .map((m) => ({
      stage: "DISPLAYED",
      text: String(m.body || "").slice(0, 120),
      buyer: m.name || "",
      uid: m.uid || "",
      t: Date.now(),
    }));
  refreshChatTraceFromStorage();

  if (stickBottom) {
    el.scrollTop = el.scrollHeight;
    el.dataset.stick = "1";
  }
}

function refreshLiveChatFromStorage() {
  chrome.storage.local.get(["psStepJournal", "psChatTranscript"], (cfg) => {
    renderLiveChat(cfg.psStepJournal, cfg.psChatTranscript);
  });
}

function syncFaceSetupUi(paired) {
  const details = document.getElementById("faceSetupDetails");
  if (!details) return;
  // Emparelhado: configuração recolhida; sem live: aberta para o código.
  if (paired) details.open = false;
  else details.open = true;
}

function updateReservasBadge() {
  const badge = document.getElementById("badgeReservas");
  if (!badge) return;
  const S = window.FleaberStudioSeller;
  const Act = window.FleaberStudioActivity;
  const n = Act
    ? Act.badgeActionableCount(sellerQueueRows, {
        isPsNeedsReview: (r) => !!S?.isPsNeedsReview?.(r),
        canActPending: (r) => !!S?.canActPending?.(r),
      })
    : (sellerQueueRows || []).filter(
        (r) => S?.isPsNeedsReview?.(r) || S?.canActPending?.(r),
      ).length;
  if (n > 0) {
    badge.textContent = String(n);
    badge.classList.remove("hidden");
  } else {
    badge.classList.add("hidden");
  }
}

function renderActivity(journal) {
  const Act = window.FleaberStudioActivity;
  let activity = [];

  if (Act?.buildCommercialFeeds) {
    const feeds = Act.buildCommercialFeeds({
      journal,
      queueRows: sellerQueueRows,
      mapJournalEntry: (e) => humanActivity(e),
    });
    activity = feeds.activity;
  } else {
    // Fallback mínimo se o modelo não carregar
    const list = Array.isArray(journal) ? journal : [];
    for (let i = list.length - 1; i >= 0 && activity.length < 40; i -= 1) {
      const h = humanActivity(list[i]);
      if (h) activity.push(h);
    }
  }

  renderFeedList(
    document.getElementById("activityFeed"),
    activity,
    "Ainda sem actividade confirmada. Reservas e cancelamentos válidos aparecem aqui.",
  );
  // reservasFeed = fila com Aceitar (renderSellerQueue) — não sobrescrever com journal
  updateReservasBadge();

  // Modo Técnico: journal completo (inclui falhas)
  const techFeed = document.getElementById("techJournalFeed");
  if (techFeed) {
    const list = Array.isArray(journal) ? journal : [];
    const techItems = [];
    let failN = 0;
    for (let i = list.length - 1; i >= 0 && techItems.length < 60; i -= 1) {
      const h = humanTechJournal(list[i]);
      if (h) {
        techItems.push(h);
        if (h.kind === "err") failN += 1;
      }
    }
    const meta = document.getElementById("techJournalMeta");
    if (meta) {
      meta.textContent = list.length
        ? `${list.length} no journal · ${failN} falhas nesta vista`
        : "vazio";
    }
    renderFeedList(
      techFeed,
      techItems,
      "Journal vazio. Falhas e sucessos PS aparecem aqui.",
    );
  }
  refreshChatTraceFromStorage();
}

function formatChatTraceLine(entry) {
  if (!entry) return null;
  const stage = String(entry.stage || "?").toUpperCase();
  const reason = entry.reason ? ` · ${entry.reason}` : "";
  const buyer = entry.buyer || entry.authorHint || "";
  const who = buyer ? ` · ${buyer}` : "";
  const text = String(entry.text || "").slice(0, 90);
  const uid = entry.uid ? ` [${String(entry.uid).slice(0, 16)}]` : "";
  const kind =
    stage === "DROPPED" ? "err" : stage === "DISPLAYED" || stage === "TRANSCRIPT" || stage === "JOURNAL_CHAT" ? "ok" : "info";
  return {
    kind,
    title: `${stage}${reason}${who}`,
    detail: `${text}${uid}`,
    t: entry.t || null,
  };
}

function renderChatTrace(traceList) {
  const el = document.getElementById("techChatTraceFeed");
  if (!el) return;
  const list = Array.isArray(traceList) ? traceList : [];
  const displayed = Array.isArray(window.__psChatDisplayedSnapshot)
    ? window.__psChatDisplayedSnapshot
    : [];
  const items = [];
  // Primeiro: o que o Chat mostra agora
  for (let i = displayed.length - 1; i >= 0 && items.length < 15; i -= 1) {
    const h = formatChatTraceLine(displayed[i]);
    if (h) items.push(h);
  }
  // Depois: pipeline CAPTURED/DROPPED/…
  for (let i = list.length - 1; i >= 0 && items.length < 60; i -= 1) {
    const h = formatChatTraceLine(list[i]);
    if (h) items.push(h);
  }
  const dropped = list.filter((e) => String(e.stage || "").toUpperCase() === "DROPPED").length;
  const meta = document.getElementById("techChatTraceMeta");
  if (meta) {
    meta.textContent = list.length
      ? `${list.length} pipeline · ${dropped} dropped · Chat mostra ${displayed.length} FB`
      : displayed.length
        ? `Chat mostra ${displayed.length} FB · pipeline vazio`
        : "vazio — activa leitura no Facebook";
  }
  renderFeedList(
    el,
    items,
    "Sem trace ainda. Com leitura activa, cada comentário Face gera CAPTURED/NORMALIZED/DROPPED aqui.",
  );
}

function refreshChatTraceFromStorage() {
  chrome.storage.local.get(["psChatTrace"], (cfg) => {
    renderChatTrace(cfg.psChatTrace);
  });
}

function renderOps(cfg, faceTab) {
  const st = cfg.psExtStats || null;
  const paired = !!(cfg.liveId && cfg.deviceToken);
  const enabled = !!cfg.enabled;
  const scriptFresh = st?.updatedAt && Date.now() - st.updatedAt <= 8000;
  const Hub = window.FleaberStudioHub;
  const liveActive =
    !!hubBundle?.hubLive && Hub?.isHubLiveActive
      ? Hub.isHubLiveActive(hubBundle.hubLive)
      : false;

  setOpsEmptyVisible(!paired);
  syncEmptyPanels(paired);
  updateTopbarActions(paired);

  const ledFace = document.getElementById("ledFace");
  if (faceTab && scriptFresh) {
    setLed(ledFace, "fb");
    document.getElementById("valFace").textContent = "A acompanhar";
    document.getElementById("hintFace").textContent = "Separador Facebook activo";
  } else if (faceTab) {
    setLed(ledFace, "warn");
    document.getElementById("valFace").textContent = "Separador aberto";
    document.getElementById("hintFace").textContent = "Activa o acompanhamento";
  } else {
    setLed(ledFace, "off");
    document.getElementById("valFace").textContent = "Sem página Face";
    document.getElementById("hintFace").textContent = "Abre o directo no Facebook";
  }

  const liveChip = document.getElementById("liveChip");
  if (paired && liveActive) {
    liveChip?.classList.remove("hidden");
  } else {
    liveChip?.classList.add("hidden");
  }

  const ledRead = document.getElementById("ledRead");
  const readingActive = paired && enabled && scriptFresh && st?.active;
  const readingPaused = paired && !enabled;
  const readingIdle = paired && enabled && !readingActive;

  if (!paired) {
    setLed(ledRead, "off");
    document.getElementById("valRead").textContent = "—";
    document.getElementById("hintRead").textContent = "Emparelha para começar";
  } else if (readingPaused) {
    setLed(ledRead, "warn");
    document.getElementById("valRead").textContent = "Pausada";
    document.getElementById("hintRead").textContent = "Clica «Retomar leitura»";
  } else if (readingActive) {
    setLed(ledRead, "on");
    document.getElementById("valRead").textContent = "Activa";
    document.getElementById("hintRead").textContent = st.lastAction
      ? `Última: ${String(st.lastAction).slice(0, 40)}`
      : "A ler comentários";
  } else {
    setLed(ledRead, "warn");
    document.getElementById("valRead").textContent = "A preparar";
    document.getElementById("hintRead").textContent =
      "Activa o acompanhamento nesta página Face";
  }

  const title = cfg.liveTitle || cfg.liveId || "";
  if (paired) {
    setLed(document.getElementById("ledLive"), enabled && scriptFresh ? "live" : "on");
    document.getElementById("valLive").textContent = "Emparelhado";
    document.getElementById("hintLive").textContent = title
      ? String(title).slice(0, 48)
      : cfg.liveId;
    document.getElementById("liveTitleShort").textContent = title
      ? `· ${String(title).slice(0, 40)}`
      : "";
  } else {
    setLed(document.getElementById("ledLive"), "off");
    document.getElementById("valLive").textContent = "Sem live";
    document.getElementById("hintLive").textContent = "Sem live emparelhada";
    document.getElementById("liveTitleShort").textContent = "";
  }

  // Saúde = acompanhamento Face/PS (não o estado Mux/Fleaber Live).
  const healthPill = document.getElementById("healthPill");
  const healthText = document.getElementById("healthText");
  const hubOnline = window.FleaberStudioHub?.isHubLiveActive
    ? window.FleaberStudioHub.isHubLiveActive(hubBundle?.hubLive)
    : false;
  if (!paired) {
    healthPill.className = "pill warn";
    healthText.textContent = "Por emparelhar";
  } else if (st?.lastError) {
    healthPill.className = "pill err";
    healthText.textContent = "Precisa de atenção";
  } else if (readingActive) {
    healthPill.className = "pill";
    healthText.textContent = hubOnline
      ? "Leitura activa"
      : "Leitura activa · Fleaber offline";
  } else if (readingPaused) {
    healthPill.className = "pill warn";
    healthText.textContent = "Leitura em pausa";
  } else if (readingIdle) {
    healthPill.className = "pill warn";
    healthText.textContent = "Face por activar";
  } else {
    healthPill.className = "pill warn";
    healthText.textContent = "A configurar Face";
  }

  // Controlos Face coerentes com estado real.
  const btnInject = document.getElementById("btnInject");
  const btnToggle = document.getElementById("btnToggle");
  const btnStop = document.getElementById("btnStopReading");
  if (btnInject) {
    // Sempre visível se emparelhado e ainda não há leitura fresca
    const showInject = paired && !readingActive;
    btnInject.classList.toggle("hidden", !showInject);
    btnInject.disabled = !paired || !faceTab;
    btnInject.textContent = "Activar leitura";
    btnInject.classList.toggle("btn-pulse", !!readingIdle && !!faceTab);
  }
  if (btnToggle) {
    const showToggle = paired && (readingActive || readingPaused);
    btnToggle.classList.toggle("hidden", !showToggle);
    btnToggle.textContent = readingPaused ? "Retomar leitura" : "Pausar leitura";
  }
  if (btnStop) {
    if (paired && (readingActive || readingPaused)) {
      btnStop.classList.remove("hidden");
      btnStop.textContent = readingPaused ? "Retomar leitura" : "Pausar leitura";
    } else {
      btnStop.classList.add("hidden");
    }
  }

  // Auto-recuperar leitura após reload da extensão / script Face morto
  if (readingIdle && faceTab) {
    void maybeAutoInjectFace(cfg, faceTab);
  }

  setLed(document.getElementById("footFace"), faceTab ? (scriptFresh ? "on" : "warn") : "off");
  setLed(
    document.getElementById("footRead"),
    paired && enabled ? (scriptFresh ? "on" : "warn") : "off",
  );
  setLed(document.getElementById("footPair"), paired ? "on" : "off");
  document.getElementById("footLastAction").textContent = st?.lastAction
    ? `Última: ${String(st.lastAction).slice(0, 36)}`
    : "";
  document.getElementById("footClock").textContent = formatClock();

  renderAlerts({
    paired,
    enabled,
    st,
    faceTab,
    metrics: hubMetrics,
    hubLive: hubBundle?.hubLive,
  });
  renderDiag(cfg, st);
  renderHubPanels(cfg);
  syncFaceSetupUi(paired);
}

async function refreshHubData(cfg) {
  if (!cfg?.liveId || !window.FleaberStudioHub) {
    hubBundle = null;
    hubMetrics = null;
    return { cleared: false };
  }
  if (hubRefreshing) return { cleared: false, busy: true };
  hubRefreshing = true;
  try {
    const Hub = window.FleaberStudioHub;
    const bundle = await Hub.loadLiveBundle(cfg.liveId, cfg.liveCatalog || []);
    hubBundle = bundle;

    if (bundle.hubLive && !Hub.isHubLiveActive(bundle.hubLive)) {
      const snapMetrics = Hub.computeMetrics({
        hubLive: bundle.hubLive,
        fomo: bundle.fomo,
        products: bundle.products,
        journal: cfg.psStepJournal,
        frozenDurationSec: cfg.liveDurationSnapshotSec,
        queueRows: sellerQueueRows,
      });
      const cleared = await archiveAndClearOpsLive(
        bundle.hubLive,
        snapMetrics,
        cfg,
      );
      hubBundle = null;
      hubMetrics = null;
      return { cleared: !!cleared };
    }

    const durationSnap = Hub.computeDurationSec(bundle.hubLive);
    if (
      durationSnap != null &&
      durationSnap !== Number(cfg.liveDurationSnapshotSec)
    ) {
      await chrome.storage.local.set({
        liveDurationSnapshotSec: durationSnap,
        liveDurationSnapshotAt: Date.now(),
      });
      cfg.liveDurationSnapshotSec = durationSnap;
    }

    hubMetrics = Hub.computeMetrics({
      hubLive: bundle.hubLive,
      fomo: bundle.fomo,
      products: bundle.products,
      journal: cfg.psStepJournal,
      frozenDurationSec: null,
      queueRows: sellerQueueRows,
    });
    return { cleared: false };
  } catch (e) {
    console.warn("[Seller Studio] hub refresh", e);
    return { cleared: false, error: String(e?.message || e) };
  } finally {
    hubRefreshing = false;
  }
}

async function refreshAll() {
  const cfg = await chrome.storage.local.get([
    "liveId",
    "liveTitle",
    "enabled",
    "deviceToken",
    "psExtStats",
    "psStepJournal",
    "psChatTranscript",
    "liveCatalog",
    "hubLiveUrl",
    "sellerHandle",
    "liveDurationSnapshotSec",
    "liveDurationSnapshotAt",
    HISTORY_STORAGE_KEY,
  ]);
  const faceTab = await findFacebookTab();
  await refreshSellerSessionUi();
  await ensureSellerProfile(cfg);
  if (sellerSession?.accessToken) {
    // Reaplica nome comercial após profile (sem fechar form — já autenticado).
    const label = document.getElementById("sellerLoggedLabel");
    const chip = document.getElementById("sellerChip");
    const display = sellerDisplayName();
    if (label) label.textContent = display;
    if (chip) chip.textContent = `· ${display}`;
  }

  if (cfg.liveId) {
    const age = refreshAll._lastHubAt ? Date.now() - refreshAll._lastHubAt : 99999;
    if (age > 4000) {
      refreshAll._lastHubAt = Date.now();
      const hubOut = await refreshHubData(cfg);
      if (hubOut?.cleared) {
        const cfg2 = await chrome.storage.local.get([
          "liveId",
          "liveTitle",
          "enabled",
          "deviceToken",
          "psExtStats",
          "psStepJournal",
          "liveCatalog",
          "hubLiveUrl",
          "sellerHandle",
        ]);
        renderOps(cfg2, faceTab);
        renderActivity([]);
        renderLiveChat([], []);
        if (!sellerSession?.accessToken) renderSellerQueue();
        return;
      }
      if (sellerSession?.accessToken) {
        const qAge = refreshAll._lastQueueAt
          ? Date.now() - refreshAll._lastQueueAt
          : 99999;
        if (qAge > 5000) {
          refreshAll._lastQueueAt = Date.now();
          await loadSellerQueue(cfg.liveId);
        }
      }
    } else if (hubMetrics && cfg.psStepJournal && window.FleaberStudioHub) {
      hubMetrics = window.FleaberStudioHub.computeMetrics({
        hubLive: hubBundle?.hubLive,
        fomo: hubBundle?.fomo,
        products: hubBundle?.products || [],
        journal: cfg.psStepJournal,
        frozenDurationSec: null,
        queueRows: sellerQueueRows,
      });
    }
  } else {
    hubBundle = null;
    hubMetrics = null;
    sellerQueueRows = [];
    attachMux("", false);
  }
  if (!sellerSession?.accessToken) renderSellerQueue();
  renderOps(cfg, faceTab);
  renderActivity(cfg.psStepJournal);
  renderLiveChat(cfg.psStepJournal, cfg.psChatTranscript);
  await refreshOllamaStatus();
}

function showPanel(name) {
  document.querySelectorAll(".panel").forEach((p) => p.classList.remove("active"));
  document.querySelectorAll(".nav-item[data-panel]").forEach((n) => n.classList.remove("active"));
  document.getElementById(`panel-${name}`)?.classList.add("active");
  document.querySelector(`.nav-item[data-panel="${name}"]`)?.classList.add("active");
  if (name === "historico") void refreshHistoryPanel();
}

async function refreshHistoryPanel() {
  const listEl = document.getElementById("historyList");
  const hint = document.getElementById("historyHint");
  if (!listEl || historyLoading) return;
  historyLoading = true;
  listEl.innerHTML = '<div class="empty">A carregar histórico…</div>';
  try {
    const Hub = window.FleaberStudioHub;
    const local = await loadLocalHistory();
    let hubRows = [];
    const sellerId = sellerSession?.userId || null;
    const cfg = await chrome.storage.local.get(["sellerHandle"]);
    const handle =
      cfg.sellerHandle ||
      local.find((e) => e.sellerHandle)?.sellerHandle ||
      null;
    if (Hub?.fetchSellerLives && (sellerId || handle)) {
      try {
        hubRows = await Hub.fetchSellerLives({
          sellerId,
          sellerHandle: handle,
          limit: 30,
        });
      } catch (e) {
        console.warn("[Seller Studio] history hub", e);
      }
    }
    const merged = Hub?.mergeHistoryLists
      ? Hub.mergeHistoryLists(local, hubRows)
      : local;
    historyListCache = merged;
    if (!merged.length) {
      listEl.innerHTML =
        '<div class="empty">Ainda sem Lives terminadas. Quando acabares um directo, aparece aqui.</div>';
      if (hint) {
        hint.textContent = "Consulta os teus directos anteriores.";
      }
      return;
    }
    if (hint) {
      hint.textContent = `${merged.length} directo(s) · toca para ver o detalhe`;
    }
    listEl.innerHTML = merged
      .map((e) => {
        const when = formatDatePt(e.wentLiveAt || e.createdAt || e.archivedAt);
        const dur =
          e.durationSec != null ? formatDuration(e.durationSec) : null;
        const statusLabel = humanLiveStatus(e.status);
        const statusClass =
          String(e.status || "").toLowerCase() === "live" ? "live" : "ended";
        const kpis = [];
        if (dur) kpis.push(`Duração ${dur}`);
        // viewer_count e VOD vêm por live (hub_lives_public / archive) — nunca da live actual.
        if (e.viewerCount != null && Number.isFinite(Number(e.viewerCount))) {
          kpis.push(`Espectadores ${e.viewerCount}`);
        }
        if (e.soldTotal != null) kpis.push(`${e.soldTotal} vendidos`);
        if (e.gmvEur != null) kpis.push(formatEuro(e.gmvEur));
        if (e.hasVod) kpis.push("Com gravação");
        else if (e.source === "hub_lives_public" || e.source === "studio_archive") {
          /* sem VOD persistido — não inventar */
        }
        return (
          `<button type="button" class="history-row" data-live-id="${escapeHtml(e.liveId)}">` +
          `<div><div class="ht">${escapeHtml(e.title || "Directo")}` +
          `<span class="history-status ${statusClass}">${escapeHtml(statusLabel)}</span></div>` +
          `<div class="hm">${escapeHtml(when)}</div></div>` +
          `<div class="hkpis">${
            kpis.length
              ? kpis.map((k) => `<span class="history-kpi">${escapeHtml(k)}</span>`).join("")
              : `<span class="history-kpi">Sem métricas extra</span>`
          }<span class="history-kpi history-kpi-cta">Ver detalhes</span></div>` +
          `</button>`
        );
      })
      .join("");
    listEl.querySelectorAll(".history-row").forEach((btn) => {
      btn.addEventListener("click", () => {
        void openHistoryDetail(btn.getAttribute("data-live-id"));
      });
    });
  } finally {
    historyLoading = false;
  }
}

function destroyHistoryPlayer() {
  if (historyHlsPlayer) {
    try {
      historyHlsPlayer.destroy();
    } catch (_) {}
    historyHlsPlayer = null;
  }
  const video = document.getElementById("historyMuxVideo");
  if (video) {
    video.removeAttribute("src");
    video.load?.();
    video.classList.remove("visible");
  }
}

function attachHistoryMux(playbackUrl) {
  destroyHistoryPlayer();
  const video = document.getElementById("historyMuxVideo");
  const empty = document.getElementById("historyMuxEmpty");
  const meta = document.getElementById("historyMuxMeta");
  if (!video) return;
  if (!playbackUrl) {
    if (empty) empty.classList.remove("hidden");
    if (meta) meta.textContent = "Sem gravação";
    return;
  }
  if (empty) empty.classList.add("hidden");
  video.classList.add("visible");
  if (meta) meta.textContent = "Replay";
  if (video.canPlayType("application/vnd.apple.mpegurl")) {
    video.src = playbackUrl;
    return;
  }
  if (window.Hls && window.Hls.isSupported()) {
    historyHlsPlayer = new window.Hls({ enableWorker: false });
    historyHlsPlayer.loadSource(playbackUrl);
    historyHlsPlayer.attachMedia(video);
    return;
  }
  if (meta) meta.textContent = "Replay não suportado neste browser";
}

function renderHistoryChat(hubMessages, transcript, journal) {
  const el = document.getElementById("historyChatFeed");
  const meta = document.getElementById("historyChatMeta");
  if (!el) return;
  const Chat = window.FleaberStudioChat;
  const items = Chat?.buildUnifiedChat
    ? Chat.buildUnifiedChat({
        hubMessages: hubMessages || [],
        journal: journal || [],
        transcript: transcript || [],
        limit: 100,
      })
    : [];
  if (!items.length) {
    el.innerHTML =
      '<li class="empty">Sem chat guardado para esta Live. Comentários Facebook só persistem se a Live foi arquivada nesta máquina (snapshot).</li>';
    if (meta) meta.textContent = "vazio";
    return;
  }
  el.innerHTML = items
    .map((m) => {
      const origin = m.origin === "facebook" ? "fb" : "fleaber";
      const badge = origin === "fb" ? "FB" : "F";
      const titleOrigin = origin === "fb" ? "Facebook" : "Fleaber";
      return (
        `<li class="chat-msg" title="${escapeHtml(titleOrigin)}">` +
        `<span class="chat-origin ${origin}" aria-label="${escapeHtml(titleOrigin)}">${badge}</span>` +
        `<div class="chat-body">` +
        `<div class="chat-name">${escapeHtml(m.name || "Utilizador")}</div>` +
        `<p class="chat-text">${escapeHtml(m.body)}</p>` +
        `</div>` +
        `<div class="chat-time">${escapeHtml(formatTimeShort(m.t))}</div>` +
        `</li>`
      );
    })
    .join("");
  const fbN = items.filter((m) => m.origin === "facebook").length;
  const flN = items.filter((m) => m.origin !== "facebook").length;
  if (meta) meta.textContent = `${items.length} · FB ${fbN} · F ${flN}`;
}

function renderHistoryQueue(rows, sourceLabel) {
  const el = document.getElementById("historyQueueFeed");
  const hint = document.getElementById("historyQueueHint");
  if (!el) return;
  const list = Array.isArray(rows) ? rows : [];
  if (!list.length) {
    el.innerHTML =
      '<li class="empty">Sem reservas guardadas para esta Live.</li>';
    if (hint) hint.textContent = sourceLabel || "";
    return;
  }
  const views = list.map((r) => queueRowView(r, { readOnly: true }));
  renderFeedList(el, views, "Sem reservas.");
  if (hint) {
    hint.textContent = `${list.length} reserva(s) · ${sourceLabel || "consulta"} · sem Aceitar/Rejeitar`;
  }
}

function renderHistoryActivity(journal, queueRows) {
  const el = document.getElementById("historyActivityFeed");
  if (!el) return;
  const Act = window.FleaberStudioActivity;
  if (Act?.buildCommercialFeeds) {
    const feeds = Act.buildCommercialFeeds({
      journal: journal || [],
      queueRows: queueRows || [],
      mapJournalEntry: (e) => humanActivity(e),
    });
    const activity = feeds.activity || [];
    if (!activity.length) {
      el.innerHTML = '<li class="empty">Sem actividade registada.</li>';
      return;
    }
    renderFeedList(el, activity, "Sem actividade.");
    return;
  }
  el.innerHTML = '<li class="empty">Sem actividade registada.</li>';
}

async function openHistoryDetail(liveId) {
  if (!liveId || !window.FleaberStudioHub) return;
  historyViewLiveId = liveId;
  const card = document.getElementById("historyDetailCard");
  const titleEl = document.getElementById("historyDetailTitle");
  const metaEl = document.getElementById("historyDetailMeta");
  const kpisEl = document.getElementById("historyDetailKpis");
  const prodsEl = document.getElementById("historyDetailProds");
  card?.classList.remove("hidden");
  card?.scrollIntoView({ behavior: "smooth", block: "start" });
  if (titleEl) titleEl.textContent = "A carregar…";
  if (metaEl) metaEl.textContent = "Consulta · só leitura · não reactiva o directo";
  if (kpisEl) kpisEl.innerHTML = "";
  if (prodsEl) prodsEl.innerHTML = '<div class="empty">…</div>';
  destroyHistoryPlayer();

  const entry = historyListCache.find((e) => e.liveId === liveId) || null;
  const snap = entry?.snapshot || null;

  try {
    const bundle = await window.FleaberStudioHub.loadLiveBundle(liveId, []);
    historyViewBundle = bundle;
    const metrics = window.FleaberStudioHub.computeMetrics({
      hubLive: bundle.hubLive,
      fomo: bundle.fomo,
      products: bundle.products,
      journal: snap?.journal || [],
      frozenDurationSec: entry?.durationSec ?? null,
      queueRows: snap?.queueRows || [],
    });
    if (titleEl) {
      titleEl.textContent =
        bundle.hubLive?.title || entry?.title || "Directo anterior";
    }
    if (metaEl) {
      const bits = [
        "Live terminada",
        "Histórico",
        "Só leitura",
        formatDatePt(
          bundle.hubLive?.went_live_at || entry?.wentLiveAt || entry?.createdAt,
        ),
        humanLiveStatus(bundle.hubLive?.status || entry?.status || "ended"),
      ];
      if (metrics.durationSec != null) {
        bits.push(`duração ${formatDuration(metrics.durationSec)}`);
      } else if (entry?.durationSec != null) {
        bits.push(`duração ${formatDuration(entry.durationSec)}`);
      }
      if (bundle.hubLive?.seller_handle || entry?.sellerHandle) {
        bits.push(`@${bundle.hubLive?.seller_handle || entry.sellerHandle}`);
      }
      metaEl.textContent = bits.join(" · ");
    }
    const chips = [];
    function add(label, value) {
      if (value == null || value === "") return;
      chips.push(
        `<div class="kpi"><div class="k">${escapeHtml(label)}</div><div class="v">${escapeHtml(String(value))}</div></div>`,
      );
    }
    add(
      "Espectadores",
      metrics.viewersFleaber != null
        ? metrics.viewersFleaber
        : entry?.viewerCount,
    );
    add(
      "Duração",
      metrics.durationSec != null
        ? formatDuration(metrics.durationSec)
        : entry?.durationSec != null
          ? formatDuration(entry.durationSec)
          : null,
    );
    add("Produtos", metrics.productsCount || snap?.products?.length || null);
    add(
      "Vendidos",
      metrics.soldTotal != null ? metrics.soldTotal : entry?.soldTotal,
    );
    add(
      "Vendas (€)",
      metrics.gmvEur != null
        ? formatEuro(metrics.gmvEur)
        : entry?.gmvEur != null
          ? formatEuro(entry.gmvEur)
          : null,
    );
    if (entry?.faceReservesOk != null) {
      add("Pedidos Face", entry.faceReservesOk);
    }
    if (kpisEl) {
      kpisEl.innerHTML = chips.length
        ? chips.join("")
        : '<div class="empty">Sem números disponíveis para este directo.</div>';
    }

    // Replay: prefer VOD; never start PS reading
    const vodId =
      bundle.hubLive?.mux_vod_playback_id ||
      entry?.muxVodPlaybackId ||
      null;
    const Hub = window.FleaberStudioHub;
    let replayUrl = "";
    if (vodId && Hub?.muxHlsUrl) {
      replayUrl = Hub.muxHlsUrl(vodId, false);
    } else if (bundle.playback?.playbackUrl && !bundle.playback?.isLive) {
      replayUrl = bundle.playback.playbackUrl;
    }
    attachHistoryMux(replayUrl);
    const hMeta = document.getElementById("historyMuxMeta");
    if (hMeta) {
      hMeta.textContent = replayUrl
        ? "Replay (VOD)"
        : "Gravação ainda não disponível";
    }

    const hubMsgs =
      (bundle.liveMessages && bundle.liveMessages.length
        ? bundle.liveMessages
        : snap?.liveMessages) || [];
    renderHistoryChat(hubMsgs, snap?.chatTranscript || [], snap?.journal || []);

    // Reservas: JWT seller (durável) → fallback snapshot local
    let queueRows = [];
    let queueSrc = "snapshot local";
    const S = window.FleaberStudioSeller;
    if (S?.queueForLive && sellerSession?.accessToken) {
      const out = await S.queueForLive(liveId, true);
      if (out.ok && Array.isArray(out.rows)) {
        queueRows = out.rows;
        queueSrc = "servidor (só leitura)";
      }
    }
    if (!queueRows.length && snap?.queueRows?.length) {
      queueRows = snap.queueRows;
      queueSrc = "snapshot ao terminar";
    }
    renderHistoryQueue(queueRows, queueSrc);

    renderHistoryActivity(snap?.journal || [], queueRows);

    const products =
      (bundle.products && bundle.products.length
        ? bundle.products
        : snap?.products) || [];
    if (prodsEl) {
      prodsEl.innerHTML = products.length
        ? products.map(productCardHtml).join("")
        : '<div class="empty">Sem catálogo guardado para este directo.</div>';
    }
  } catch (e) {
    if (titleEl) titleEl.textContent = entry?.title || "Live";
    if (metaEl) metaEl.textContent = `Consulta falhou: ${e.message || e}`;
    if (prodsEl) {
      prodsEl.innerHTML =
        '<div class="empty">Não foi possível carregar o detalhe.</div>';
    }
    if (snap) {
      renderHistoryChat(
        snap.liveMessages || [],
        snap.chatTranscript || [],
        snap.journal || [],
      );
      renderHistoryQueue(snap.queueRows || [], "snapshot local (offline Hub)");
      renderHistoryActivity(snap.journal || [], snap.queueRows || []);
      if (prodsEl && snap.products?.length) {
        prodsEl.innerHTML = snap.products.map(productCardHtml).join("");
      }
    }
  }
}

function closeHistoryDetail() {
  historyViewLiveId = null;
  historyViewBundle = null;
  destroyHistoryPlayer();
  document.getElementById("historyDetailCard")?.classList.add("hidden");
}

function openClassicPopup() {
  chrome.runtime.sendMessage({ type: "open_classic_popup" }, () => {
    void chrome.runtime.lastError;
  });
}

async function doUnpair() {
  historyViewLiveId = null;
  historyViewBundle = null;
  await chrome.storage.local.remove(OPS_STORAGE_KEYS);
  hubBundle = null;
  hubMetrics = null;
  sellerQueueRows = [];
  lastMuxUrl = "";
  attachMux("", false);
  setMsg(statusMsg, "Desemparelhado. Sessão vendedor mantida.", "");
  setOpsMsg("Desemparelhado. Sessão vendedor mantida.", "");
  document.getElementById("ollama").checked = false;
  document.getElementById("strictRef").checked = true;
  await refreshAll();
}

async function toggleReading() {
  const cfg = await chrome.storage.local.get(["enabled", "liveId"]);
  if (!cfg.liveId) {
    setMsg(statusMsg, "Emparelha primeiro.", "warn");
    return;
  }
  const next = !cfg.enabled;
  await chrome.storage.local.set({ enabled: next });
  setMsg(statusMsg, `Leitura: <b>${next ? "activa" : "em pausa"}</b>`, next ? "ok" : "warn");
  await refreshAll();
}

const statusMsg = document.getElementById("statusMsg");
const techStatus = document.getElementById("techStatus");
const codeEl = document.getElementById("code");

async function doPairWithCode(codeRaw) {
  const code = String(codeRaw || "").trim();
  if (code.length !== 6) {
    setOpsMsg("Código inválido.", "err");
    return false;
  }
  setOpsMsg("A emparelhar…");
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/ps-pairing-claim`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        code,
        device_id: "ps-chrome-ext",
        app_version: "1.7.6-studio",
      }),
    });
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || `HTTP ${res.status}`);
    const ctx = data.live_context || {};
    historyViewLiveId = null;
    historyViewBundle = null;
    closeHistoryDetail();
    await chrome.storage.local.set({
      liveId: data.live_id,
      deviceToken: data.device_token,
      deviceId: data.device_id || "ps-chrome-ext",
      liveTitle: ctx.live_title || "Live",
      liveCatalog: catalogFromContext(ctx),
      liveActiveRef: activeRefFromContext(ctx),
      sellerHandle: data.seller_handle || ctx.seller_handle || null,
      hubLiveUrl: data.hub_live_url || ctx.hub_live_url || null,
      enabled: true,
      strictRefMode: true,
      psExtStats: null,
      liveDurationSnapshotSec: null,
      liveDurationSnapshotAt: null,
    });
    setOpsMsg(
      `<span class="ok">Emparelhado: ${escapeHtml(ctx.live_title || data.live_id)}</span><br>` +
        `<span class="warn">A activar leitura no Facebook…</span>`,
      "ok",
    );
    refreshAll._lastHubAt = 0;
    await refreshAll();
    // Após emparelhar (e após reload da extensão) o script Face pode estar morto
    _lastAutoInjectAt = 0;
    await injectIntoFaceTab({ quiet: false });
    return true;
  } catch (e) {
    setOpsMsg(String(e.message || e), "err");
    return false;
  }
}

document.getElementById("studioVersion").textContent = APP_VERSION_LABEL;

document.querySelectorAll(".nav-item[data-panel]").forEach((btn) => {
  btn.addEventListener("click", () => showPanel(btn.getAttribute("data-panel")));
});

document.getElementById("btnClassic")?.addEventListener("click", openClassicPopup);
document.getElementById("btnOpenClassicTech")?.addEventListener("click", openClassicPopup);
document.getElementById("btnShowSellerLogin")?.addEventListener("click", () => {
  sellerLoginFormOpen = true;
  document.getElementById("btnShowSellerLogin")?.classList.add("hidden");
  document.getElementById("sellerLoginForm")?.classList.remove("hidden");
  document.getElementById("sellerEmail")?.focus();
});
document.getElementById("btnCancelSellerLogin")?.addEventListener("click", () => {
  sellerLoginFormOpen = false;
  document.getElementById("sellerLoginForm")?.classList.add("hidden");
  document.getElementById("btnShowSellerLogin")?.classList.remove("hidden");
  const pw = document.getElementById("sellerPassword");
  if (pw) pw.value = "";
});
document.getElementById("btnPair").addEventListener("click", () => {
  void doPairWithCode(codeEl?.value);
});
document.getElementById("btnPairEmpty")?.addEventListener("click", () => {
  void doPairWithCode(document.getElementById("codeEmpty")?.value);
});
document.getElementById("codeEmpty")?.addEventListener("keydown", (ev) => {
  if (ev.key === "Enter") void doPairWithCode(ev.target.value);
});

document.getElementById("btnInject").addEventListener("click", () => {
  void injectIntoFaceTab();
});
document.getElementById("btnFocusFace")?.addEventListener("click", () => {
  void focusFacebookTab();
});
document.getElementById("btnToggle").addEventListener("click", () => void toggleReading());
document.getElementById("btnStopReading").addEventListener("click", () => void toggleReading());
document.getElementById("btnUnpair").addEventListener("click", () => void doUnpair());
document.getElementById("btnUnpairTop").addEventListener("click", () => void doUnpair());
document.getElementById("btnHistoryClose")?.addEventListener("click", () => closeHistoryDetail());
document.getElementById("btnRefreshHub").addEventListener("click", async () => {
  refreshAll._lastHubAt = 0;
  refreshAll._lastQueueAt = 0;
  setMsg(statusMsg, "A actualizar…");
  await refreshAll();
  const cfg = await chrome.storage.local.get([
    "liveId",
    "deviceToken",
    "enabled",
    "psExtStats",
  ]);
  const faceTab = await findFacebookTab();
  const st = cfg.psExtStats;
  const stale =
    !st?.updatedAt || Date.now() - st.updatedAt > 8000 || !st?.active;
  if (cfg.liveId && cfg.enabled && faceTab && stale) {
    _lastAutoInjectAt = 0;
    await injectIntoFaceTab({ quiet: false });
  } else {
    setMsg(statusMsg, "Actualizado.", "ok");
  }
});

document.getElementById("btnSellerLogin")?.addEventListener("click", async () => {
  const email = document.getElementById("sellerEmail")?.value || "";
  const password = document.getElementById("sellerPassword")?.value || "";
  setMsg(statusMsg, "A entrar…");
  const res = await window.FleaberStudioSeller.signIn(email, password);
  if (!res.ok) {
    setMsg(statusMsg, `Login falhou: ${res.error}`, "err");
    // Manter formulário aberto após falha.
    sellerLoginFormOpen = true;
    return;
  }
  sellerLoginFormOpen = false;
  document.getElementById("sellerPassword").value = "";
  setMsg(statusMsg, "Sessão vendedor activa.", "ok");
  refreshAll._lastQueueAt = 0;
  await refreshAll();
  const cfg = await chrome.storage.local.get(["liveId"]);
  if (cfg.liveId) await loadSellerQueue(cfg.liveId);
});

document.getElementById("btnSellerLogout")?.addEventListener("click", async () => {
  sellerLoginFormOpen = false;
  sellerProfile = null;
  await window.FleaberStudioSeller.signOut();
  sellerQueueRows = [];
  setMsg(statusMsg, "Sessão vendedor terminada.", "ok");
  await refreshAll();
});

document.getElementById("btnRefreshQueueTech")?.addEventListener("click", async () => {
  const cfg = await chrome.storage.local.get(["liveId"]);
  refreshAll._lastQueueAt = 0;
  await loadSellerQueue(cfg.liveId);
  setMsg(document.getElementById("techStatus"), "Fila forçada.", "ok");
});

document.getElementById("ollama").addEventListener("change", () => {
  const enabled = !!document.getElementById("ollama").checked;
  const tier = document.getElementById("aiTier").value || "auto";
  chrome.storage.local.set(
    {
      ollamaEnabled: enabled,
      ollamaUrl: "http://127.0.0.1:11434",
      ollamaTier: tier,
      ollamaModel: resolveOllamaModel(tier, null),
    },
    () => void refreshOllamaStatus(),
  );
});
document.getElementById("strictRef").addEventListener("change", () => {
  chrome.storage.local.set({
    strictRefMode: !!document.getElementById("strictRef").checked,
  });
});
document.getElementById("aiTier").addEventListener("change", () => {
  const tier = document.getElementById("aiTier").value || "auto";
  chrome.storage.local.set({
    ollamaTier: tier,
    ollamaModel: resolveOllamaModel(tier, null),
  }, () => void refreshOllamaStatus());
});

document.getElementById("btnProbe").addEventListener("click", async () => {
  const tab = await findFacebookTab();
  if (!tab?.id) {
    setMsg(techStatus, "Abre o Facebook Live.", "err");
    return;
  }
  setMsg(techStatus, "A sondar…");
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content_loader.js"],
    });
  } catch (e) {
    setMsg(techStatus, `Falha: ${e.message || e}`, "err");
    return;
  }
  let summary = null;
  let lastErr = "";
  for (let i = 0; i < 8; i += 1) {
    await new Promise((r) => setTimeout(r, 400));
    try {
      summary = await chrome.tabs.sendMessage(tab.id, { type: "probe_author_identity" });
      if (summary?.ok) break;
      lastErr = summary?.error || "sem ok";
      if (summary?.error === "probe_not_ready") continue;
      break;
    } catch (e) {
      lastErr = e.message || String(e);
    }
  }
  if (!summary?.ok) {
    setMsg(techStatus, `Sonda falhou: ${lastErr}`, "err");
    return;
  }
  const blob = new Blob([JSON.stringify(summary, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `ps_author_identity_${Date.now()}.json`;
  a.click();
  URL.revokeObjectURL(url);
  setMsg(techStatus, `Sonda OK: ${summary.comment_blocks || 0} blocos.`, "ok");
});

document.getElementById("btnExportIdentity").addEventListener("click", () => {
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
        setMsg(techStatus, "Sonda vazia.", "warn");
        return;
      }
      const blob = new Blob([JSON.stringify(payload, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `ps_author_identity_${Date.now()}.json`;
      a.click();
      URL.revokeObjectURL(url);
      setMsg(techStatus, "Sonda exportada.", "ok");
    },
  );
});

document.getElementById("btnExportJournal").addEventListener("click", () => {
  chrome.storage.local.get(["psStepJournal", "liveId"], (cfg) => {
    const list = Array.isArray(cfg.psStepJournal) ? cfg.psStepJournal : [];
    if (!list.length) {
      setMsg(techStatus, "Journal vazio.", "warn");
      return;
    }
    const blob = new Blob(
      [JSON.stringify({ live_id: cfg.liveId || null, steps: list }, null, 2)],
      { type: "application/json" },
    );
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `ps_step_journal_${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
    setMsg(techStatus, `Journal: ${list.length} passos.`, "ok");
  });
});

document.getElementById("btnClearJournal").addEventListener("click", () => {
  chrome.storage.local.set({ psStepJournal: [] }, () => {
    setMsg(techStatus, "Journal limpo.", "ok");
    void refreshAll();
  });
});

document.getElementById("btnResetRun").addEventListener("click", () => {
  chrome.storage.local.set(
    { psStepJournal: [], psExtStats: null, psRunResetToken: Date.now() },
    () => {
      setMsg(techStatus, "Estado da corrida limpo.", "ok");
      void refreshAll();
    },
  );
});

chrome.storage.onChanged.addListener(() => {
  void refreshAll();
});

void refreshAll();
setInterval(() => {
  void refreshAll();
}, 1500);
