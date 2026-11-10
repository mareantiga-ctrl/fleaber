/** Painel flutuante arrastável — Logs + separador Passos (confirmação QA). */

const PANEL_ID = "fleaber-ps-float-panel";
const PANEL_DOM_VERSION = "1.5.35";
const PANEL_JOURNAL_MAX = 300;
/** @type {{ ts: string, kind: string, message: string, detail: string }[]} */
const panelJournal = [];

/** @type {(payload: { ok: boolean, reason: string, uiActual?: string, uiMatchesExpected?: boolean }) => void | null} */
let qaConfirmResolver = null;

function lab2JournalEndpoint() {
  if (/^https?:\/\/(127\.0\.0\.1|localhost):8765\b/i.test(location.origin || "")) {
    return `${location.origin}/ps_ai/lab2/journal`;
  }
  return "http://127.0.0.1:8765/ps_ai/lab2/journal";
}

/** Grava a nota do Passos no journal Lab (mesmo se postMessage falhar). */
function persistUiNoteToLab(payload) {
  const uiActual = String(
    payload?.uiActual || payload?.ui_actual || payload?.note || "",
  ).trim();
  const body = {
    type: "confirm_ui_input",
    reason: payload?.reason || "proceed",
    ok: payload?.ok !== false,
    ui_actual: uiActual || null,
    uiActual: uiActual || null,
    ui_matches_expected: !uiActual,
    source: "panel_direct",
    page_url: String(location.href || "").slice(0, 200),
  };
  try {
    const sid = window.__FLEABER_LAB2_SESSION_ID__;
    if (sid) body.session_id = sid;
  } catch (_) {}
  // fire-and-forget — não bloquear Prosseguir
  try {
    void fetch(lab2JournalEndpoint(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      keepalive: true,
    }).catch(() => {});
  } catch (_) {}
}

function ensurePanel() {
  let root = document.getElementById(PANEL_ID);
  if (root && root.dataset.fpsVersion !== PANEL_DOM_VERSION) {
    root.remove();
    root = null;
  }
  if (root) return root;

  root = document.createElement("div");
  root.id = PANEL_ID;
  root.dataset.fpsVersion = PANEL_DOM_VERSION;
  root.innerHTML = `
    <div class="fps-head" title="Arrasta para mover">
      <span class="fps-title">Fleaber PS</span>
      <span class="fps-badge">ON</span>
      <div class="fps-head-actions">
        <button type="button" class="fps-copy" title="Copiar logs">Copiar</button>
        <button type="button" class="fps-clear" title="Limpar eventos">Limpar</button>
        <button type="button" class="fps-min" title="Minimizar" aria-label="Minimizar">—</button>
      </div>
    </div>
    <div class="fps-tabs" role="tablist">
      <button type="button" class="fps-tab is-active" data-tab="log" role="tab" aria-selected="true">Logs</button>
      <button type="button" class="fps-tab" data-tab="passos" role="tab" aria-selected="false">Passos</button>
    </div>
    <div class="fps-body">
      <div class="fps-pane fps-pane-log is-active" data-pane="log">
        <div class="fps-status">A iniciar…</div>
        <div class="fps-log"></div>
      </div>
      <div class="fps-pane fps-pane-passos" data-pane="passos" hidden>
        <div class="fps-qa-idle muted">Sem passo activo. O Lab envia aqui o esperado.</div>
        <div class="fps-qa" hidden>
          <div class="fps-qa-meta"></div>
          <div class="fps-qa-comment"></div>
          <div class="fps-qa-expected-label fps-qa-expected-legacy-label">Resumo:</div>
          <div class="fps-qa-expected fps-qa-expected-legacy"></div>
          <div class="fps-qa-panes">
            <div class="fps-qa-pane" data-pane="tcl">
              <div class="fps-qa-pane-label">TCL · Operações</div>
              <div class="fps-qa-pane-body fps-qa-pane-tcl"></div>
            </div>
            <div class="fps-qa-pane" data-pane="probeA">
              <div class="fps-qa-pane-label">Probe A · Hub / qty</div>
              <div class="fps-qa-pane-body fps-qa-pane-probeA"></div>
            </div>
            <div class="fps-qa-pane" data-pane="probeB">
              <div class="fps-qa-pane-label">Probe B · Buyer</div>
              <div class="fps-qa-pane-body fps-qa-pane-probeB"></div>
            </div>
          </div>
          <label class="fps-qa-actual-label" for="fps-qa-actual">
            Se NÃO bater: escreve o que vês (vazio = correcto)
          </label>
          <textarea id="fps-qa-actual" class="fps-qa-actual" rows="4" placeholder="Ex.: Lara — Camisola Nike Azul L × 2 (só isto)"></textarea>
          <div class="fps-qa-bd" hidden></div>
          <div class="fps-qa-actions">
            <button type="button" class="fps-qa-confirm">Prosseguir</button>
            <button type="button" class="fps-qa-stop">Parar</button>
          </div>
          <div class="fps-qa-hint muted">Vazio + Prosseguir = OK. Com texto = diferença para o agente.</div>
        </div>
      </div>
    </div>
  `;

  const style = document.createElement("style");
  style.textContent = `
    #${PANEL_ID} {
      position: fixed; z-index: 2147483646;
      top: 80px; right: 16px; width: 380px;
      height: min(80vh, 680px); max-height: 80vh;
      background: #101518; color: #e8eef0; border-radius: 14px;
      box-shadow: 0 12px 40px rgba(0,0,0,.45);
      font: 12px/1.4 system-ui, sans-serif;
      border: 1px solid #2a343b; overflow: hidden;
      display: flex; flex-direction: column;
    }
    #${PANEL_ID}.fps-collapsed {
      height: auto; max-height: none; width: auto; min-width: 140px;
    }
    #${PANEL_ID}.fps-collapsed .fps-body,
    #${PANEL_ID}.fps-collapsed .fps-tabs { display: none; }
    #${PANEL_ID}.fps-collapsed .fps-badge,
    #${PANEL_ID}.fps-collapsed .fps-copy,
    #${PANEL_ID}.fps-collapsed .fps-clear { display: none !important; }
    #${PANEL_ID} .fps-head {
      display: flex; align-items: center; gap: 6px;
      padding: 8px 10px; background: #152026; cursor: move;
      user-select: none; flex-wrap: nowrap;
    }
    #${PANEL_ID} .fps-title {
      font-weight: 800; color: #00A3AD;
      min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      flex: 1 1 auto;
    }
    #${PANEL_ID}.fps-collapsed .fps-title { flex: 0 1 auto; max-width: 88px; }
    #${PANEL_ID} .fps-head-actions {
      display: flex; align-items: center; gap: 6px; flex: 0 0 auto; margin-left: auto;
    }
    #${PANEL_ID} .fps-badge {
      font-size: 10px; font-weight: 700; color: #6dd4a8;
      background: rgba(109,212,168,.12); padding: 2px 6px; border-radius: 999px;
      flex: 0 0 auto;
    }
    #${PANEL_ID} .fps-min,
    #${PANEL_ID} .fps-copy,
    #${PANEL_ID} .fps-clear {
      border: 0; color: #fff; height: 28px; min-width: 28px;
      border-radius: 8px; cursor: pointer; font-weight: 800;
      flex: 0 0 auto; pointer-events: auto; position: relative; z-index: 2;
    }
    #${PANEL_ID} .fps-min {
      background: #007782; font-size: 18px; line-height: 1; padding: 0 8px;
    }
    #${PANEL_ID}.fps-collapsed .fps-head { cursor: pointer; }
    #${PANEL_ID}.fps-collapsed .fps-head:hover { background: #1a2a32; }
    #${PANEL_ID} .fps-copy { font-size: 10px; padding: 0 8px; background: #007782; }
    #${PANEL_ID} .fps-clear { font-size: 10px; padding: 0 8px; background: #4a4a4a; }
    #${PANEL_ID} .fps-copy.fps-copied { background: #6dd4a8; color: #101518; }
    #${PANEL_ID}.fps-collapsed .fps-min {
      min-width: 40px; height: 36px; font-size: 22px;
    }
    #${PANEL_ID} .fps-tabs {
      display: flex; gap: 0; background: #0c1216; border-bottom: 1px solid #2a343b;
      flex: 0 0 auto;
    }
    #${PANEL_ID} .fps-tab {
      flex: 1; border: 0; background: transparent; color: #98a1aa;
      font-weight: 700; font-size: 12px; padding: 8px; cursor: pointer;
    }
    #${PANEL_ID} .fps-tab.is-active {
      color: #00A3AD; background: #152026;
      box-shadow: inset 0 -2px 0 #00A3AD;
    }
    #${PANEL_ID} .fps-body {
      padding: 8px 10px 12px; min-height: 0; flex: 1 1 auto;
      display: flex; flex-direction: column; gap: 8px; overflow: hidden;
    }
    #${PANEL_ID} .fps-pane {
      display: none; flex-direction: column; gap: 8px;
      flex: 1 1 auto; min-height: 0; overflow: hidden;
    }
    #${PANEL_ID} .fps-pane.is-active { display: flex; }
    #${PANEL_ID} .fps-status { color: #98a1aa; font-size: 11px; flex: 0 0 auto; }
    #${PANEL_ID} .fps-log {
      flex: 1 1 auto; min-height: 0;
      overflow-y: auto; overscroll-behavior: contain;
      display: flex; flex-direction: column; gap: 6px;
    }
    #${PANEL_ID} .fps-row {
      background: #1a2228; border-radius: 8px; padding: 8px;
      border-left: 3px solid #007782;
    }
    #${PANEL_ID} .fps-row.err { border-left-color: #ff8a80; }
    #${PANEL_ID} .fps-row.warn { border-left-color: #ffb74d; }
    #${PANEL_ID} .fps-row.ok { border-left-color: #6dd4a8; }
    #${PANEL_ID} .fps-row .t { color: #98a1aa; font-size: 10px; margin-bottom: 2px; }
    #${PANEL_ID} .fps-row .m { color: #e8eef0; word-break: break-word; }
    #${PANEL_ID} .muted { color: #98a1aa; }
    #${PANEL_ID} .fps-qa {
      display: flex; flex-direction: column; gap: 8px;
      flex: 1 1 auto; min-height: 0; overflow-y: auto;
    }
    #${PANEL_ID} .fps-qa-meta {
      font-weight: 800; color: #00A3AD; font-size: 13px;
    }
    #${PANEL_ID} .fps-qa-comment {
      background: #1a2228; border-radius: 8px; padding: 8px;
      border-left: 3px solid #007782; word-break: break-word;
    }
    #${PANEL_ID} .fps-qa-expected-label,
    #${PANEL_ID} .fps-qa-actual-label {
      font-size: 11px; color: #98a1aa;
    }
    #${PANEL_ID} .fps-qa-expected {
      background: #152026; border: 1px solid #2a343b; border-radius: 10px;
      padding: 10px; white-space: pre-wrap; font-size: 13px; line-height: 1.45;
      font-weight: 600; color: #e8eef0;
    }
    #${PANEL_ID} .fps-qa-panes {
      display: flex; flex-direction: column; gap: 6px;
    }
    #${PANEL_ID} .fps-qa-pane {
      background: #152026; border: 1px solid #2a343b; border-radius: 8px;
      padding: 8px; border-left: 3px solid #00A3AD;
    }
    #${PANEL_ID} .fps-qa-pane[data-pane="probeA"] { border-left-color: #7e57c2; }
    #${PANEL_ID} .fps-qa-pane[data-pane="probeB"] { border-left-color: #ffb74d; }
    #${PANEL_ID} .fps-qa-pane-label {
      font-size: 10px; font-weight: 800; color: #00A3AD;
      text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 4px;
    }
    #${PANEL_ID} .fps-qa-pane[data-pane="probeA"] .fps-qa-pane-label { color: #b39ddb; }
    #${PANEL_ID} .fps-qa-pane[data-pane="probeB"] .fps-qa-pane-label { color: #ffcc80; }
    #${PANEL_ID} .fps-qa-pane-body {
      white-space: pre-wrap; font-size: 12px; line-height: 1.4; color: #e8eef0;
    }
    #${PANEL_ID} .fps-qa-pane.is-empty { opacity: 0.45; }
    #${PANEL_ID} .fps-qa-expected-legacy-label.is-hidden,
    #${PANEL_ID} .fps-qa-expected-legacy.is-hidden { display: none; }
    #${PANEL_ID} .fps-qa-actual {
      width: 100%; box-sizing: border-box;
      background: #0c1216; color: #e8eef0; border: 1px solid #3a454c;
      border-radius: 10px; padding: 8px 10px; font: 12px/1.4 system-ui, sans-serif;
      resize: vertical; min-height: 72px;
    }
    #${PANEL_ID} .fps-qa-actual:focus {
      outline: none; border-color: #00A3AD;
    }
    #${PANEL_ID} .fps-qa-bd {
      background: #1a2228; border-radius: 8px; padding: 8px;
      white-space: pre-wrap; font-size: 11px; border-left: 3px solid #ffb74d;
    }
    #${PANEL_ID} .fps-qa-bd.ok { border-left-color: #6dd4a8; }
    #${PANEL_ID} .fps-qa-bd.err { border-left-color: #ff8a80; }
    #${PANEL_ID} .fps-qa-actions {
      display: flex; flex-wrap: wrap; gap: 6px; flex: 0 0 auto;
    }
    #${PANEL_ID} .fps-qa-confirm {
      flex: 1 1 160px; border: 0; background: #0a8f5c; color: #fff;
      font-weight: 800; font-size: 14px; padding: 12px 10px; border-radius: 10px;
      cursor: pointer; min-height: 48px;
    }
    #${PANEL_ID} .fps-qa-confirm:disabled { opacity: 0.45; cursor: default; }
    #${PANEL_ID} .fps-qa-stop {
      border: 0; background: #4a4a4a; color: #fff; font-weight: 700;
      padding: 10px 12px; border-radius: 10px; cursor: pointer;
    }
    #${PANEL_ID} .fps-qa-hint { font-size: 10px; }
    #${PANEL_ID} .fps-qa-idle { padding: 12px 4px; }
  `;
  document.documentElement.appendChild(style);
  document.documentElement.appendChild(root);

  const head = root.querySelector(".fps-head");
  const headActions = root.querySelector(".fps-head-actions");
  let drag = null;
  head?.addEventListener("pointerdown", (e) => {
    if (e.target.closest(".fps-head-actions")) return;
    if (root.classList.contains("fps-collapsed")) return;
    drag = {
      x: e.clientX - root.offsetLeft,
      y: e.clientY - root.offsetTop,
    };
    head.setPointerCapture?.(e.pointerId);
  });
  head?.addEventListener("pointermove", (e) => {
    if (!drag) return;
    root.style.left = `${Math.max(0, e.clientX - drag.x)}px`;
    root.style.top = `${Math.max(0, e.clientY - drag.y)}px`;
    root.style.right = "auto";
  });
  head?.addEventListener("pointerup", () => {
    drag = null;
  });

  root.querySelector(".fps-min")?.addEventListener("click", (e) => {
    e.stopPropagation();
    root.classList.toggle("fps-collapsed");
  });
  head?.addEventListener("click", () => {
    if (root.classList.contains("fps-collapsed")) {
      root.classList.remove("fps-collapsed");
    }
  });
  root.querySelector(".fps-copy")?.addEventListener("click", (e) => {
    e.stopPropagation();
    void copyPanelJournal();
  });
  root.querySelector(".fps-clear")?.addEventListener("click", (e) => {
    e.stopPropagation();
    clearPanelJournal();
  });

  root.querySelectorAll(".fps-tab").forEach((tab) => {
    tab.addEventListener("click", () => selectPanelTab(tab.dataset.tab || "log"));
  });

  root.querySelector(".fps-qa-confirm")?.addEventListener("click", () => {
    const ta = root.querySelector(".fps-qa-actual");
    const uiActual = String(ta?.value || "").trim();
    resolveQaConfirm({
      ok: true,
      reason: "proceed",
      uiActual,
      uiMatchesExpected: !uiActual,
    });
  });
  root.querySelector(".fps-qa-stop")?.addEventListener("click", () => {
    const ta = root.querySelector(".fps-qa-actual");
    const uiActual = String(ta?.value || "").trim();
    resolveQaConfirm({
      ok: false,
      reason: "stop",
      uiActual,
      uiMatchesExpected: !uiActual,
    });
  });

  headActions?.addEventListener("click", (e) => e.stopPropagation());

  return root;
}

function selectPanelTab(name) {
  const root = ensurePanel();
  root.querySelectorAll(".fps-tab").forEach((t) => {
    const on = t.dataset.tab === name;
    t.classList.toggle("is-active", on);
    t.setAttribute("aria-selected", on ? "true" : "false");
  });
  root.querySelectorAll(".fps-pane").forEach((p) => {
    const on = p.dataset.pane === name;
    p.classList.toggle("is-active", on);
    p.hidden = !on;
  });
  if (name === "passos") {
    root.classList.remove("fps-collapsed");
  }
}

function setPanelStatus(text) {
  const root = ensurePanel();
  const el = root.querySelector(".fps-status");
  if (el) el.textContent = text || "";
}

function resolveQaConfirm(payload) {
  const fn = qaConfirmResolver;
  qaConfirmResolver = null;
  const root = document.getElementById(PANEL_ID);
  const btn = root?.querySelector(".fps-qa-confirm");
  const hint = root?.querySelector(".fps-qa-hint");
  if (btn) btn.disabled = true;
  const uiActual = String(
    payload?.uiActual || payload?.ui_actual || payload?.note || "",
  ).trim();
  const normalized = {
    ...payload,
    uiActual,
    ui_actual: uiActual,
    note: uiActual,
    uiMatchesExpected: !uiActual,
  };
  // 1) HTTP directo → journal + AGENT_INBOX (fonte de verdade para o agente)
  persistUiNoteToLab(normalized);
  try {
    void fetch(
      lab2JournalEndpoint().replace(/\/journal$/, "/agent_note"),
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text: uiActual,
          ui_actual: uiActual,
          batchNum: window.__FLEABER_LAB2_BATCH_NUM__ || null,
          source: "panel_agent_note",
        }),
        keepalive: true,
      },
    ).catch(() => {});
  } catch (_) {}
  // 2) DOM event (atravessa isolated world ↔ página Lab)
  try {
    document.dispatchEvent(
      new CustomEvent("fleaber-ps-qa-response", {
        detail: normalized,
        bubbles: true,
      }),
    );
  } catch (_) {}
  // 3) postMessage (caminho clássico)
  if (fn) fn(normalized);
  try {
    window.postMessage(
      { source: "fleaber-ps-panel", type: "qa_response", payload: normalized },
      "*",
    );
  } catch (_) {}
  if (hint) {
    hint.textContent = uiActual
      ? `Nota enviada ao journal: «${uiActual.slice(0, 80)}${uiActual.length > 80 ? "…" : ""}»`
      : "OK enviado (caixa vazia).";
    hint.classList.remove("muted");
  }
}

function showQaPrompt(payload) {
  const root = ensurePanel();
  selectPanelTab("passos");
  const idle = root.querySelector(".fps-qa-idle");
  const box = root.querySelector(".fps-qa");
  if (idle) idle.hidden = true;
  if (box) box.hidden = false;
  const meta = root.querySelector(".fps-qa-meta");
  const comment = root.querySelector(".fps-qa-comment");
  const expected = root.querySelector(".fps-qa-expected");
  const expectedLabel = root.querySelector(".fps-qa-expected-legacy-label");
  const bd = root.querySelector(".fps-qa-bd");
  const confirmBtn = root.querySelector(".fps-qa-confirm");
  const actual = root.querySelector(".fps-qa-actual");
  if (meta) meta.textContent = payload.meta || "Passo";
  if (comment) {
    const buyer = payload.buyer ? `${payload.buyer}: ` : "";
    comment.textContent = buyer + (payload.comment || "");
  }
  const panes = payload.expectPanes || null;
  const hasPanes =
    panes &&
    (panes.tcl || panes.probeA || panes.probeB || panes.hub || panes.buyer);
  if (expected) {
    expected.textContent = payload.expectedHuman || "(sem esperado)";
    expected.classList.toggle("is-hidden", !!hasPanes);
  }
  if (expectedLabel) {
    expectedLabel.classList.toggle("is-hidden", !!hasPanes);
    if (!hasPanes) {
      expectedLabel.textContent = "No ecrã Operações deve estar:";
    }
  }
  const setPane = (key, text) => {
    const body = root.querySelector(`.fps-qa-pane-${key}`);
    const wrap = root.querySelector(`.fps-qa-pane[data-pane="${key}"]`);
    const t = String(text || "").trim();
    if (body) body.textContent = t || "(—)";
    if (wrap) wrap.classList.toggle("is-empty", !t);
  };
  const panesWrap = root.querySelector(".fps-qa-panes");
  if (panesWrap) panesWrap.hidden = !hasPanes;
  if (hasPanes) {
    setPane("tcl", panes.tcl || "");
    setPane("probeA", panes.probeA || panes.hub || "");
    setPane("probeB", panes.probeB || panes.buyer || "");
  } else {
    setPane("tcl", "");
    setPane("probeA", "");
    setPane("probeB", "");
  }
  // NÃO limpar a caixa só porque o Lab reenvia o prompt — só com resetActual.
  if (actual) {
    if (payload.resetActual === true) {
      actual.value = "";
    }
    actual.disabled = payload.waitingConfirm === false;
  }
  if (bd) {
    if (payload.bdText) {
      bd.hidden = false;
      bd.textContent = payload.bdText;
      bd.className = `fps-qa-bd ${payload.bdKind || ""}`;
    } else {
      bd.hidden = true;
      bd.textContent = "";
      bd.className = "fps-qa-bd";
    }
  }
  if (confirmBtn) {
    confirmBtn.disabled = payload.waitingConfirm === false;
    confirmBtn.textContent =
      payload.waitingConfirm === false ? "Aguarde…" : "Prosseguir";
  }
  const hint = root.querySelector(".fps-qa-hint");
  if (hint && payload.waitingConfirm !== false) {
    hint.textContent =
      "Vazio + Prosseguir = OK. Com texto = diferença registada para o agente (grava no journal).";
    hint.classList.add("muted");
  }
}

function setQaBdResult(text, kind) {
  const root = ensurePanel();
  const bd = root.querySelector(".fps-qa-bd");
  if (!bd) return;
  bd.hidden = !text;
  bd.textContent = text || "";
  bd.className = `fps-qa-bd ${kind || ""}`;
}

function clearQaPrompt() {
  const root = document.getElementById(PANEL_ID);
  if (!root) return;
  const idle = root.querySelector(".fps-qa-idle");
  const box = root.querySelector(".fps-qa");
  const actual = root.querySelector(".fps-qa-actual");
  if (idle) idle.hidden = false;
  if (box) box.hidden = true;
  if (actual) actual.value = "";
  qaConfirmResolver = null;
}

function waitQaConfirm() {
  const root = ensurePanel();
  selectPanelTab("passos");
  const confirmBtn = root.querySelector(".fps-qa-confirm");
  if (confirmBtn) {
    confirmBtn.disabled = false;
    confirmBtn.textContent = "Prosseguir";
  }
  return new Promise((resolve) => {
    qaConfirmResolver = resolve;
  });
}

function buildPanelJournalText() {
  const header = `Fleaber PS panel ${new Date().toISOString()}\n`;
  if (panelJournal.length === 0) return `${header}(sem eventos)`;
  const body = panelJournal.map(formatJournalLine).join("\n");
  return header + body;
}

function formatJournalLine(e) {
  return `[${e.ts}] ${e.kind || "info"} ${e.message}${e.detail ? ` — ${e.detail}` : ""}`;
}

async function copyPanelJournal() {
  const root = document.getElementById(PANEL_ID);
  const btn = root?.querySelector(".fps-copy");
  const text = buildPanelJournalText();
  try {
    await navigator.clipboard.writeText(text);
  } catch (_) {
    const ta = document.createElement("textarea");
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    ta.remove();
  }
  if (btn) {
    btn.classList.add("fps-copied");
    btn.textContent = "OK";
    setTimeout(() => {
      btn.classList.remove("fps-copied");
      btn.textContent = "Copiar";
    }, 1200);
  }
}

function appendPanelEvent(kindOrObj, message, detail) {
  let kind = kindOrObj;
  let msg = message;
  let det = detail;
  if (kindOrObj && typeof kindOrObj === "object") {
    kind = kindOrObj.kind || "";
    msg = kindOrObj.message || "";
    det = kindOrObj.detail || "";
  }
  const root = ensurePanel();
  const log = root.querySelector(".fps-log");
  if (!log) return;
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const ss = String(now.getSeconds()).padStart(2, "0");
  const ts = `${hh}:${mm}:${ss}`;
  panelJournal.unshift({
    ts,
    kind: kind || "",
    message: msg || "",
    detail: det || "",
  });
  while (panelJournal.length > PANEL_JOURNAL_MAX) panelJournal.pop();

  const row = document.createElement("div");
  row.className = `fps-row ${kind || ""}`;
  row.innerHTML = `<div class="t">${ts}</div><div class="m"></div>`;
  row.querySelector(".m").textContent = det ? `${msg} — ${det}` : msg;
  log.prepend(row);
  while (log.children.length > 80) log.removeChild(log.lastChild);
}

function clearPanelJournal() {
  panelJournal.length = 0;
  const root = document.getElementById(PANEL_ID);
  const log = root?.querySelector(".fps-log");
  if (log) log.innerHTML = "";
}

export {
  ensurePanel,
  setPanelStatus,
  appendPanelEvent,
  copyPanelJournal,
  buildPanelJournalText,
  clearPanelJournal,
  showQaPrompt,
  setQaBdResult,
  clearQaPrompt,
  waitQaConfirm,
  selectPanelTab,
};
