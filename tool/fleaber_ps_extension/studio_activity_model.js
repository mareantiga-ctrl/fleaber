/**
 * Read-model comercial do Seller Studio (Staging).
 * Uma reserva real = uma entidade; journal técnico fica à parte.
 * Estados UX: No saco → Aceite (aguarda pagamento) → Vendida | Cancelada.
 * NÃO altera lifecycle backend — só apresentação.
 */
(function (global) {
  function normBuyer(s) {
    return String(s || "")
      .trim()
      .toLowerCase()
      // «mariana soares5» (OCR colado) → «mariana soares»
      .replace(/([a-zà-ú])\d{1,3}\b/g, "$1")
      .replace(/\s+/g, " ")
      .trim();
  }

  function normRef(s) {
    return String(s || "")
      .trim()
      .replace(/^#/, "")
      .toUpperCase();
  }

  function queueMatchKey(row) {
    const buyer = normBuyer(
      row.external_display_name ||
        row.buyer_display_name ||
        row.display_name ||
        "",
    );
    const ref = normRef(row.resolved_ref_slug || row.ref_code || "");
    return `${buyer}|${ref}`;
  }

  function journalMatchKey(entry) {
    const buyer = normBuyer(
      entry.buyer || entry.displayName || entry.author || "",
    );
    const ref = normRef(
      entry.ref_out ||
        entry.ref_in ||
        entry.refSlug ||
        entry.ref_slug ||
        entry.ref ||
        entry.resolved_ref_slug ||
        entry.slot_in ||
        "",
    );
    return `${buyer}|${ref}`;
  }

  /** «mariana» e «mariana soares» = mesma pessoa para a mesma REF. */
  function buyersSoftEqual(a, b) {
    const x = normBuyer(a);
    const y = normBuyer(b);
    if (!x || !y) return false;
    if (x === y) return true;
    return x.startsWith(y) || y.startsWith(x);
  }

  function sameJournalEntity(a, b) {
    const ra = normRef(
      a.ref_out || a.ref || a.refSlug || a.ref_slug || a.resolved_ref_slug || "",
    );
    const rb = normRef(
      b.ref_out || b.ref || b.refSlug || b.ref_slug || b.resolved_ref_slug || "",
    );
    if (!ra || !rb || ra !== rb) return false;
    return buyersSoftEqual(
      a.buyer || a.displayName || "",
      b.buyer || b.displayName || "",
    );
  }

  function journalActionRank(entry) {
    const action = String(entry.action || "").toLowerCase();
    const intent = String(entry.intent || "").toLowerCase();
    if (intent === "cancel" || /cancel/.test(action)) return 30;
    if (action === "superseded" || action === "updated") return 20;
    if (action === "created" || intent === "reserve") return 10;
    return 0;
  }

  function isCancelEntry(entry) {
    const action = String(entry?.action || "").toLowerCase();
    const intent = String(entry?.intent || "").toLowerCase();
    return intent === "cancel" || /cancel/.test(action);
  }

  /** create+supersede da 1.ª reserva → título «Reservou» (não «Actualizou»). */
  function preferReserveVerb(item) {
    if (!item || !item.title) return item;
    const title = String(item.title).replace(
      /·\s*Actualizou reserva\b/i,
      "· Reservou",
    );
    return title === item.title ? item : { ...item, title };
  }

  /**
   * Sem fila (ex. not_allowed): 1 linha por entidade buyer≈|REF
   * só para create+supersede (mesma msg). Cancel mantém linha própria.
   */
  function collapseJournalFeedItems(items) {
    const out = [];
    for (const item of items) {
      const entry = item._entry;
      if (!entry) {
        out.push(item);
        continue;
      }
      // Cancel nunca funde com create/supersede — fica histórico visível
      if (isCancelEntry(entry)) {
        out.push(item);
        continue;
      }
      const idx = out.findIndex(
        (o) =>
          o._entry &&
          !isCancelEntry(o._entry) &&
          sameJournalEntity(o._entry, entry),
      );
      if (idx < 0) {
        out.push(item);
        continue;
      }
      const prev = out[idx];
      const prevRank = journalActionRank(prev._entry);
      const nextRank = journalActionRank(entry);
      const prevT = Date.parse(prev.t) || 0;
      const nextT = Date.parse(item.t) || 0;
      if (
        nextRank > prevRank ||
        (nextRank === prevRank && nextT >= prevT)
      ) {
        const mergedCreateSupersede =
          (prevRank === 10 && nextRank === 20) ||
          (prevRank === 20 && nextRank === 10);
        out[idx] = mergedCreateSupersede ? preferReserveVerb(item) : item;
      } else if (prevRank === 20 && nextRank === 10) {
        out[idx] = preferReserveVerb(prev);
      }
    }
    return out.map(({ _entry, ...rest }) => rest);
  }

  function isBuyerCancelled(row) {
    const notes = String(row.notes || "").toLowerCase();
    return (
      notes.includes("buyer_cancelled") ||
      notes.includes("cancelado pelo comprador") ||
      notes.includes("buyer canceled")
    );
  }

  /**
   * Estados comerciais (terminologia PT seller) — read-model only.
   * pending = No saco (ainda sem bloqueio exclusivo)
   * accepted = Reservada · aguarda pagamento (janela 5 dias)
   * converted = Vendida
   */
  function commercialState(row) {
    const st = String(row.status || "").toLowerCase();
    if (isBuyerCancelled(row)) {
      return {
        code: "cancelled",
        label: "Cancelada",
        short: "Cancelada",
        kind: "err",
        active: false,
      };
    }
    if (st === "pending") {
      return {
        code: "bag",
        label: "No saco · por aceitar",
        short: "No saco",
        hint: "Pedido recebido — ainda não reservado",
        kind: "warn",
        active: true,
      };
    }
    if (st === "accepted") {
      return {
        code: "accepted",
        label: "Reservada · aguarda pagamento",
        short: "Reservada",
        hint: "Reservado — aguarda pagamento (5 dias)",
        kind: "ok",
        active: true,
      };
    }
    if (st === "converted") {
      return {
        code: "sold",
        label: "Vendida",
        short: "Vendida",
        kind: "ok",
        active: false,
      };
    }
    if (st === "rejected") {
      return {
        code: "rejected",
        label: "Rejeitada",
        short: "Rejeitada",
        kind: "err",
        active: false,
      };
    }
    if (st === "expired") {
      return {
        code: "expired",
        label: "Expirada",
        short: "Expirada",
        kind: "warn",
        active: false,
      };
    }
    return null;
  }

  function commercialFromQueueRow(row) {
    const state = commercialState(row);
    if (!state) return null;
    const buyer =
      row.external_display_name ||
      row.buyer_display_name ||
      row.display_name ||
      "Comprador";
    const ref = row.resolved_ref_slug || row.ref_code || "";
    const qty = row.requested_qty ?? row.quantity ?? 1;
    const refBit = ref ? ` ${String(ref).replace(/^#/, "").toUpperCase()}` : "";
    return {
      id: row.id || null,
      kind: state.kind,
      title: `${refBit.trim() || "Pedido"} ×${qty}`,
      detail: `${buyer} · ${state.label}`,
      t: row.effective_at || row.updated_at || row.created_at || row.detected_at || null,
      isReserve: true,
      matchKey: queueMatchKey(row),
      status: state.code,
      statusLabel: state.label,
      buyer,
      ref: normRef(ref),
      qty,
      source: "queue",
    };
  }

  /**
   * Actividade comercial: 1 linha por reserva da fila (canónica).
   * Com fila carregada, journal reserve/cancel omitido se a entidade já está na fila.
   */
  function buildCommercialFeeds({ journal, queueRows, mapJournalEntry }) {
    const queue = Array.isArray(queueRows) ? queueRows : [];
    const list = Array.isArray(journal) ? journal : [];
    const fromQueue = [];

    queue.forEach((row) => {
      const item = commercialFromQueueRow(row);
      if (!item) return;
      fromQueue.push(item);
    });

    const queueKeys = new Set(fromQueue.map((q) => q.matchKey).filter(Boolean));
    const queueRefs = new Set(fromQueue.map((q) => q.ref).filter(Boolean));

    const fromJournal = [];
    for (let i = list.length - 1; i >= 0 && fromJournal.length < 80; i -= 1) {
      const entry = list[i];
      const h = typeof mapJournalEntry === "function" ? mapJournalEntry(entry) : null;
      if (!h) continue;
      const jk = journalMatchKey(entry);
      // Fila canónica presente → não duplicar lifecycle (Reservou / cancelou / rejeitada)
      if (fromQueue.length > 0) {
        if (h.isReserve) continue;
        if (jk && jk !== "|" && queueKeys.has(jk)) continue;
        const jRef = normRef(
          entry.ref_out || entry.ref || entry.refSlug || "",
        );
        if (jRef && queueRefs.has(jRef) && /cancel|rejeit/i.test(h.title || "")) {
          continue;
        }
        // Soft match buyer|ref vs fila
        const softHit = fromQueue.some(
          (q) =>
            q.ref &&
            jRef &&
            q.ref === jRef &&
            buyersSoftEqual(q.buyer, entry.buyer || ""),
        );
        if (softHit && (h.isReserve || /cancel|rejeit/i.test(h.title || ""))) {
          continue;
        }
      }
      fromJournal.push({ ...h, source: "journal", matchKey: jk, _entry: entry });
    }

    // Sem fila: colapsar created+superseded da mesma REF/comprador (caso «5 ccc5»)
    const journalCollapsed =
      fromQueue.length === 0
        ? collapseJournalFeedItems(fromJournal)
        : fromJournal.map(({ _entry, ...rest }) => rest);

    const useful = [...fromQueue, ...journalCollapsed];
    useful.sort((a, b) => {
      const ta = Date.parse(a.t) || 0;
      const tb = Date.parse(b.t) || 0;
      return tb - ta;
    });

    const reserves = useful.filter((u) => u.isReserve || u.kind === "warn");
    return {
      activity: useful.slice(0, 40),
      reserves: reserves.slice(0, 40),
    };
  }

  /**
   * Reservas Face OPERACIONAIS = pending (no saco) + accepted (aguarda pagamento).
   * Canceladas / rejeitadas / expiradas / vendidas NÃO entram.
   */
  function activeFaceReserveCount(queueRows) {
    const queue = Array.isArray(queueRows) ? queueRows : [];
    return queue.filter((r) => {
      if (isBuyerCancelled(r)) return false;
      const st = String(r.status || "").toLowerCase();
      return st === "pending" || st === "accepted";
    }).length;
  }

  /** Legado / analytics: entidades na fila (incl. rejeitadas) ou journal creates. */
  function canonicalReserveCount({ queueRows, journal }) {
    const active = activeFaceReserveCount(queueRows);
    if (Array.isArray(queueRows) && queueRows.length > 0) {
      return active;
    }

    const list = Array.isArray(journal) ? journal : [];
    const entities = []; // { buyer, ref, cancelled }

    function findEntity(entry) {
      return entities.findIndex((e) => sameJournalEntity(e, entry));
    }

    list.forEach((e) => {
      const intent = String(e.intent || "").toLowerCase();
      const action = String(e.action || "").toLowerCase();
      const ref = normRef(
        e.ref_out || e.ref || e.refSlug || e.ref_slug || e.slot_in || "",
      );
      const buyer = e.buyer || e.displayName || "";
      if (!ref) return;

      if (intent === "cancel" || /cancel/.test(action)) {
        const i = findEntity({ buyer, ref_out: ref });
        if (i >= 0) entities[i].cancelled = true;
        return;
      }
      if (e?.ok !== true) return;
      if (!(intent === "reserve" || /created|superseded|updated/.test(action))) {
        return;
      }
      const i = findEntity({ buyer, ref_out: ref });
      if (i >= 0) {
        entities[i].cancelled = false;
        // manter o nome mais completo
        if (normBuyer(buyer).length > normBuyer(entities[i].buyer).length) {
          entities[i].buyer = buyer;
        }
      } else {
        entities.push({ buyer, ref_out: ref, cancelled: false });
      }
    });
    return entities.filter((e) => !e.cancelled).length;
  }

  /** Badge = pedidos reais a precisar de acção (não linhas de journal). */
  function badgeActionableCount(queueRows, predicates) {
    const rows = Array.isArray(queueRows) ? queueRows : [];
    const isReview = predicates?.isPsNeedsReview || (() => false);
    const canAct = predicates?.canActPending || (() => false);
    return rows.filter((r) => isReview(r) || canAct(r)).length;
  }

  /**
   * Resumo comercial por artigo (para cards de produto).
   * Prioridade: vendida > reservada > no saco > cancelada recente > disponível.
   */
  function productCommercialSummary(product, queueRows) {
    const rows = Array.isArray(queueRows) ? queueRows : [];
    const id = String(product?.liveItemId || "");
    const ref = normRef(product?.refCode || "");
    const matched = rows.filter((r) => {
      if (id && String(r.live_item_id || "") === id) return true;
      const rr = normRef(r.resolved_ref_slug || r.ref_code || "");
      return ref && rr && ref === rr;
    });
    if (!matched.length) {
      return {
        line: "Disponível",
        code: "available",
        kind: "",
      };
    }
    const states = matched.map((r) => ({ row: r, state: commercialState(r) })).filter((x) => x.state);
    const sold = states.filter((x) => x.state.code === "sold");
    const accepted = states.filter((x) => x.state.code === "accepted");
    const bag = states.filter((x) => x.state.code === "bag");
    const cancelled = states.filter(
      (x) => x.state.code === "cancelled" || x.state.code === "rejected",
    );
    if (sold.length) {
      const q = sold.reduce((s, x) => s + (x.row.requested_qty || x.row.quantity || 1), 0);
      return { line: `Vendida ×${q}`, code: "sold", kind: "ok" };
    }
    if (accepted.length) {
      const q = accepted.reduce((s, x) => s + (x.row.requested_qty || x.row.quantity || 1), 0);
      return {
        line: `Reservada ×${q}`,
        sub: "Aguarda pagamento",
        code: "accepted",
        kind: "ok",
      };
    }
    if (bag.length) {
      const q = bag.reduce((s, x) => s + (x.row.requested_qty || x.row.quantity || 1), 0);
      return {
        line: `No saco ×${q}`,
        sub: "A aguardar decisão",
        code: "bag",
        kind: "warn",
      };
    }
    if (cancelled.length && !bag.length && !accepted.length) {
      return {
        line: "Disponível",
        sub: "Última reserva cancelada",
        code: "available_after_cancel",
        kind: "",
      };
    }
    return { line: "Disponível", code: "available", kind: "" };
  }

  global.FleaberStudioActivity = {
    normBuyer,
    normRef,
    queueMatchKey,
    journalMatchKey,
    buyersSoftEqual,
    sameJournalEntity,
    isBuyerCancelled,
    commercialState,
    commercialFromQueueRow,
    buildCommercialFeeds,
    badgeActionableCount,
    canonicalReserveCount,
    activeFaceReserveCount,
    productCommercialSummary,
  };
})(typeof window !== "undefined" ? window : globalThis);
