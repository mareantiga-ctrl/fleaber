/**
 * Chat unificado do directo — só camada de apresentação.
 *
 * MVP (v1.7.22+): Chat do Studio = **só eventos comerciais** (reserva / cancel /
 * supersede). Chat social Facebook (skipped_chat + transcript) fica fora até pós-MVP.
 * Hub Fleaber (tips/chat) mantém-se.
 *
 * Dedupe: uid/comment id primeiro; NÃO apagar duas mensagens humanas iguais com uids distintos.
 */
(function (global) {
  function normText(s) {
    return String(s || "")
      .trim()
      .toLowerCase()
      .replace(/\s+/g, " ");
  }

  function timeBucket(isoOrMs, widthMs) {
    const ms =
      typeof isoOrMs === "number"
        ? isoOrMs
        : Date.parse(isoOrMs || "") || 0;
    if (!ms) return "0";
    const w = widthMs || 2000;
    return String(Math.floor(ms / w));
  }

  function dedupeKey(origin, name, body, t) {
    return `${origin}|${normText(name)}|${normText(body)}|${timeBucket(t)}`;
  }

  function isDirtyDisplayBody(body, name) {
    const b = String(body || "").trim();
    const n = String(name || "").trim();
    if (!b) return true;
    if (/\bcomentario\b/i.test(b) && b.split(/\s+/).length <= 4) return true;
    if (/\d+\s*min\.?\s*$/i.test(b)) return true;
    const bodyCompact = b.replace(/\s+/g, "").toLowerCase();
    if (/1min|soaresteste|soaresrrr|soarescancela/i.test(bodyCompact)) return true;
    if (/^(comentario)$/i.test(b)) return true;
    if (!/\s/.test(b) && b.length < 28 && /[a-zà-ú]{2,}\d/i.test(bodyCompact)) {
      const last = (n.split(/\s+/).pop() || "").toLowerCase();
      if (last && bodyCompact.startsWith(last)) return true;
    }
    return false;
  }

  function cleanlinessScore(msg) {
    let s = 0;
    if (msg.source === "hub_live_messages_public") s += 40;
    if (msg.source === "psChatTranscript") s += 20;
    if (msg.uid) s += 15;
    if (msg.id && String(msg.id).startsWith("hub:")) s += 10;
    if (!isDirtyDisplayBody(msg.body, msg.name)) s += 25;
    if (msg.name && msg.name !== "Comprador") s += 5;
    if (/\s/.test(String(msg.body || ""))) s += 2;
    return s;
  }

  function splitBuyerBody(buyer, raw) {
    const text = String(raw || "").trim();
    const b = String(buyer || "").trim();
    if (b && text.toLowerCase().startsWith(b.toLowerCase())) {
      return { name: b, body: text.slice(b.length).trim() || text };
    }
    if (!b && text) {
      const parts = text.split(/\s+/);
      for (let n = Math.min(3, parts.length - 1); n >= 1; n -= 1) {
        const nameParts = parts.slice(0, n);
        const name = nameParts.join(" ");
        const body = parts.slice(n).join(" ");
        if (
          n >= 2 &&
          nameParts.every((w) => /^[A-ZÀ-Ú][\p{L}'’.-]*$/u.test(w)) &&
          body &&
          !/^(quero|cancela|rrr|teste|bla)/i.test(name)
        ) {
          return { name, body };
        }
      }
    }
    return { name: b || "Comprador", body: text };
  }

  /** Journal PS → Chat: só acções comerciais (MVP). */
  function isCommercialJournalEntry(entry) {
    if (!entry || entry.ok === false) return false;
    const action = String(entry.action || "").toLowerCase();
    const intent = String(entry.intent || "").toLowerCase();
    if (action === "skipped_chat" || action === "mux_playback_error") return false;
    if (intent === "chat" || intent === "ambiguous" || intent === "tech") return false;
    if (intent === "reserve" || intent === "cancel") return true;
    if (
      /^(created|superseded|updated|cancelled|canceled|rejected|accepted)$/i.test(
        action,
      )
    ) {
      return true;
    }
    return false;
  }

  function fromHubRow(row) {
    if (!row) return null;
    const kind = String(row.kind || "chat").toLowerCase();
    if (kind === "system") return null;
    if (!["chat", "tip"].includes(kind)) return null;
    const ch = String(row.channel || "fleaber").toLowerCase();
    // MVP: sem chat Facebook via Hub (só Fleaber / tips)
    if (ch === "facebook") return null;
    const origin = "fleaber";
    const body = String(row.body || "").trim();
    if (!body && kind !== "tip") return null;
    const tip =
      row.tip_amount != null && Number(row.tip_amount) > 0
        ? `Gorjeta ${Number(row.tip_amount).toFixed(2)} €`
        : "";
    const msg = {
      id: row.id ? `hub:${row.id}` : null,
      uid: row.id || null,
      origin,
      name: row.sender_label || "Utilizador",
      body: body || tip || "(mensagem)",
      t: row.created_at || null,
      kind,
      source: "hub_live_messages_public",
    };
    if (isDirtyDisplayBody(msg.body, msg.name)) return null;
    return msg;
  }

  function fromJournalEntry(entry) {
    if (!isCommercialJournalEntry(entry)) return null;
    const raw = String(entry.raw || "").trim();
    if (!raw) return null;
    const buyer = String(entry.buyer || "").trim();
    const { name, body } = splitBuyerBody(buyer, raw);
    const commentUid = String(entry.comment_uid || "").trim();
    const eventId = commentUid
      ? commentUid
      : entry.t
        ? `j:${entry.t}:${normText(name)}:${normText(body)}`
        : null;
    const intent = String(entry.intent || "").toLowerCase();
    const action = String(entry.action || "").toLowerCase();
    const msg = {
      id: eventId ? `juid:${eventId}` : null,
      uid: eventId,
      origin: "facebook",
      name,
      body: body.slice(0, 280),
      t: entry.t || null,
      kind: intent === "cancel" || /cancel/.test(action) ? "cancel" : "reserve",
      source: "psStepJournal",
      commercial: true,
    };
    if (isDirtyDisplayBody(msg.body, msg.name)) return null;
    return msg;
  }

  function fromTranscriptRow(row) {
    // MVP: transcript NÃO alimenta o Chat (era a fonte de «teste»/«blabla»/lixo Face).
    // Função mantida para testes/pós-MVP.
    void row;
    return null;
  }

  /**
   * Timeline MVP: Hub Fleaber → journal comercial.
   * Transcript ignorado até pós-MVP (chat social FB).
   */
  function buildUnifiedChat({ hubMessages, journal, transcript, limit }) {
    const lim = Math.max(20, Math.min(Number(limit) || 80, 120));
    const byUid = new Map();
    const bySoft = new Map();
    const out = [];
    void transcript; // pós-MVP

    function consider(msg) {
      if (!msg || !msg.body) return;
      if (isDirtyDisplayBody(msg.body, msg.name)) return;
      const score = cleanlinessScore(msg);
      const tMs = Date.parse(msg.t) || 0;

      const cross = out.find((o) => {
        if (o.source === msg.source) return false;
        if (normText(o.name) !== normText(msg.name)) return false;
        if (normText(o.body) !== normText(msg.body)) return false;
        const ot = Date.parse(o.t) || 0;
        return Math.abs(ot - tMs) < 3000;
      });
      if (cross) {
        if (cleanlinessScore(cross) >= score) return;
        const idx = out.indexOf(cross);
        if (idx >= 0) out.splice(idx, 1);
        if (cross.uid) byUid.delete(cross.uid);
      }

      if (msg.uid) {
        const prev = byUid.get(msg.uid);
        if (prev) {
          if (cleanlinessScore(prev) >= score) return;
          const idx = out.indexOf(prev);
          if (idx >= 0) out.splice(idx, 1);
        }
        byUid.set(msg.uid, msg);
        out.push(msg);
        return;
      }

      const softKey = `${normText(msg.name)}|${normText(msg.body)}|${timeBucket(msg.t, 2000)}`;
      const prevSoft = bySoft.get(softKey);
      if (prevSoft && cleanlinessScore(prevSoft) >= score) return;
      if (prevSoft) {
        const idx = out.indexOf(prevSoft);
        if (idx >= 0) out.splice(idx, 1);
      }
      bySoft.set(softKey, msg);
      out.push(msg);
    }

    (Array.isArray(hubMessages) ? hubMessages : []).forEach((row) => {
      consider(fromHubRow(row));
    });
    (Array.isArray(journal) ? journal : []).forEach((entry) => {
      consider(fromJournalEntry(entry));
    });

    out.sort((a, b) => (Date.parse(a.t) || 0) - (Date.parse(b.t) || 0));
    return out.slice(-lim);
  }

  global.FleaberStudioChat = {
    normText,
    dedupeKey,
    isDirtyDisplayBody,
    isCommercialJournalEntry,
    fromHubRow,
    fromJournalEntry,
    fromTranscriptRow,
    buildUnifiedChat,
  };
})(typeof window !== "undefined" ? window : globalThis);
