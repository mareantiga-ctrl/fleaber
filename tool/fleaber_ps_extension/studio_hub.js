/**
 * Read-only Hub / Staging data for Seller Studio.
 * Uses existing anon surfaces only — no new Edge, no seller JWT, no rule changes.
 */
(function (global) {
  const env = () => global.FLEABER_STUDIO_ENV || {};

  function headers() {
    const key = env().anonKey || "";
    return {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    };
  }

  /** Prefer JWT vendedor para stock (anon não vê batata_live_item_stock nestes items). */
  async function stockHeaders() {
    try {
      const S = global.FleaberStudioSeller;
      if (S?.refreshIfNeeded) {
        const s = await S.refreshIfNeeded();
        if (s?.accessToken) {
          const key = env().anonKey || "";
          return {
            apikey: key,
            Authorization: `Bearer ${s.accessToken}`,
            "Content-Type": "application/json",
            Prefer: "return=representation",
          };
        }
      }
    } catch (_) {}
    return headers();
  }

  function restBase() {
    return `${(env().supabaseUrl || "").replace(/\/$/, "")}/rest/v1`;
  }

  function fnBase() {
    return `${(env().supabaseUrl || "").replace(/\/$/, "")}/functions/v1`;
  }

  async function getJson(url) {
    const res = await fetch(url, { headers: headers() });
    if (!res.ok) {
      const t = await res.text().catch(() => "");
      throw new Error(`http_${res.status}:${t.slice(0, 120)}`);
    }
    return res.json();
  }

  async function postRpc(name, body) {
    const res = await fetch(`${restBase()}/rpc/${name}`, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify(body || {}),
    });
    if (!res.ok) {
      const t = await res.text().catch(() => "");
      throw new Error(`rpc_${name}_${res.status}:${t.slice(0, 120)}`);
    }
    return res.json();
  }

  async function fetchHubLive(liveId) {
    if (!liveId) return null;
    const rows = await getJson(
      `${restBase()}/hub_lives_public?id=eq.${encodeURIComponent(liveId)}&select=id,title,status,is_active,viewer_count,mux_playback_id,mux_vod_playback_id,went_live_at,seller_handle,seller_id,publish_backend,created_at&limit=1`,
    );
    return Array.isArray(rows) && rows[0] ? rows[0] : null;
  }

  /** Lives do vendedor já públicas no Hub (Staging) — só campos fiáveis da view. */
  async function fetchSellerLives({ sellerId, sellerHandle, limit = 30 } = {}) {
    const lim = Math.min(Math.max(Number(limit) || 30, 1), 50);
    let url = "";
    if (sellerId) {
      url = `${restBase()}/hub_lives_public?seller_id=eq.${encodeURIComponent(sellerId)}&select=id,title,status,is_active,viewer_count,went_live_at,seller_handle,seller_id,created_at,mux_vod_playback_id&order=created_at.desc&limit=${lim}`;
    } else if (sellerHandle) {
      url = `${restBase()}/hub_lives_public?seller_handle=eq.${encodeURIComponent(sellerHandle)}&select=id,title,status,is_active,viewer_count,went_live_at,seller_handle,seller_id,created_at,mux_vod_playback_id&order=created_at.desc&limit=${lim}`;
    } else {
      return [];
    }
    const rows = await getJson(url);
    return Array.isArray(rows) ? rows : [];
  }

  /** Live operacionalmente activa (não ended / draft). */
  function isHubLiveActive(hubLive) {
    if (!hubLive) return false;
    const st = String(hubLive.status || "").toLowerCase();
    if (st === "ended" || st === "cancelled" || st === "canceled") return false;
    if (hubLive.is_active === true) return true;
    return st === "live";
  }

  /**
   * Duração: só conta enquanto activa.
   * Sem ended_at na view pública — se terminada e sem frozenSec, devolve null (não continua a contar).
   */
  function computeDurationSec(hubLive, frozenSec, nowMs) {
    if (frozenSec != null && Number.isFinite(Number(frozenSec))) {
      return Math.max(0, Math.floor(Number(frozenSec)));
    }
    const started = hubLive?.went_live_at;
    if (!started) return null;
    const t0 = Date.parse(started);
    if (Number.isNaN(t0)) return null;
    if (!isHubLiveActive(hubLive)) return null;
    const now = nowMs != null ? Number(nowMs) : Date.now();
    return Math.max(0, Math.floor((now - t0) / 1000));
  }

  /**
   * Entrada de histórico comercial (campos fiáveis + snapshot local).
   * snapshot: FB transcript / journal / fila / produtos — sobrevive ao clearOps.
   * Dados Hub (reservas, messages Fleaber, VOD) re-lêem-se por live_id.
   */
  function buildHistoryEntry({
    hubLive,
    metrics,
    frozenDurationSec,
    archivedAt,
    snapshot,
  } = {}) {
    const live = hubLive || {};
    const id = live.id || null;
    if (!id) return null;
    const dur =
      frozenDurationSec != null && Number.isFinite(Number(frozenDurationSec))
        ? Math.max(0, Math.floor(Number(frozenDurationSec)))
        : null;
    const snap = snapshot && typeof snapshot === "object" ? snapshot : null;
    return {
      liveId: id,
      title: live.title || null,
      status: live.status || "ended",
      isActive: false,
      wentLiveAt: live.went_live_at || null,
      createdAt: live.created_at || null,
      sellerHandle: live.seller_handle || null,
      sellerId: live.seller_id || null,
      viewerCount:
        metrics?.viewersFleaber != null
          ? metrics.viewersFleaber
          : live.viewer_count != null
            ? Number(live.viewer_count)
            : null,
      durationSec: dur,
      soldTotal: metrics?.soldTotal != null ? metrics.soldTotal : null,
      gmvEur: metrics?.gmvEur != null ? metrics.gmvEur : null,
      productsCount: metrics?.productsCount != null ? metrics.productsCount : null,
      faceReservesOk:
        metrics?.fbReservesOk != null ? metrics.fbReservesOk : null,
      pendingQueueTotal:
        metrics?.pendingQueueTotal != null ? metrics.pendingQueueTotal : null,
      hasVod: !!(live.mux_vod_playback_id),
      muxVodPlaybackId: live.mux_vod_playback_id || null,
      muxPlaybackId: live.mux_playback_id || null,
      archivedAt: archivedAt || new Date().toISOString(),
      source: "studio_archive",
      readOnly: true,
      snapshot: snap
        ? {
            chatTranscript: Array.isArray(snap.chatTranscript)
              ? snap.chatTranscript.slice(-200)
              : [],
            journal: Array.isArray(snap.journal)
              ? snap.journal.slice(-200)
              : [],
            queueRows: Array.isArray(snap.queueRows)
              ? snap.queueRows.slice(0, 120)
              : [],
            products: Array.isArray(snap.products)
              ? snap.products.slice(0, 60)
              : [],
            liveMessages: Array.isArray(snap.liveMessages)
              ? snap.liveMessages.slice(0, 80)
              : [],
          }
        : null,
    };
  }

  /** Junta snapshots locais + rows Hub (sem inventar duração). */
  function mergeHistoryLists(localEntries, hubRows) {
    const byId = new Map();
    (Array.isArray(hubRows) ? hubRows : []).forEach((row) => {
      if (!row?.id) return;
      if (isHubLiveActive(row)) return;
      byId.set(row.id, {
        liveId: row.id,
        title: row.title || null,
        status: row.status || "ended",
        isActive: false,
        wentLiveAt: row.went_live_at || null,
        createdAt: row.created_at || null,
        sellerHandle: row.seller_handle || null,
        sellerId: row.seller_id || null,
        viewerCount: row.viewer_count != null ? Number(row.viewer_count) : null,
        durationSec: null,
        soldTotal: null,
        gmvEur: null,
        productsCount: null,
        hasVod: !!(row.mux_vod_playback_id),
        archivedAt: null,
        source: "hub_lives_public",
        readOnly: true,
      });
    });
    (Array.isArray(localEntries) ? localEntries : []).forEach((e) => {
      if (!e?.liveId) return;
      const prev = byId.get(e.liveId) || {};
      byId.set(e.liveId, {
        ...prev,
        ...e,
        durationSec:
          e.durationSec != null
            ? e.durationSec
            : prev.durationSec != null
              ? prev.durationSec
              : null,
        soldTotal: e.soldTotal != null ? e.soldTotal : prev.soldTotal ?? null,
        gmvEur: e.gmvEur != null ? e.gmvEur : prev.gmvEur ?? null,
        productsCount:
          e.productsCount != null ? e.productsCount : prev.productsCount ?? null,
        viewerCount:
          e.viewerCount != null ? e.viewerCount : prev.viewerCount ?? null,
        hasVod: !!(e.hasVod || prev.hasVod),
        muxVodPlaybackId: e.muxVodPlaybackId || prev.muxVodPlaybackId || null,
        snapshot: e.snapshot || prev.snapshot || null,
        readOnly: true,
        source: e.source || prev.source || "studio_archive",
      });
    });
    return [...byId.values()].sort((a, b) => {
      const ta = Date.parse(a.wentLiveAt || a.createdAt || a.archivedAt || 0) || 0;
      const tb = Date.parse(b.wentLiveAt || b.createdAt || b.archivedAt || 0) || 0;
      return tb - ta;
    });
  }

  async function fetchSellerProfile({ sellerId, sellerHandle } = {}) {
    let url = "";
    if (sellerId) {
      url = `${restBase()}/hub_profiles_public?id=eq.${encodeURIComponent(sellerId)}&select=id,handle,full_name,photo_url&limit=1`;
    } else if (sellerHandle) {
      url = `${restBase()}/hub_profiles_public?handle=eq.${encodeURIComponent(sellerHandle)}&select=id,handle,full_name,photo_url&limit=1`;
    } else {
      return null;
    }
    try {
      const rows = await getJson(url);
      return Array.isArray(rows) && rows[0] ? rows[0] : null;
    } catch (_) {
      return null;
    }
  }

  /**
   * URL pública Hub — espelha HubUrls.liveWebHash (deploy hash / nginx sem rewrites).
   * Usa handle canónico da live, não inventa rotas.
   */
  function buildHubLiveWebUrl(handle, liveId, origin) {
    const h = String(handle || "")
      .trim()
      .replace(/^\/+|\/+$/g, "")
      .toLowerCase();
    const id = String(liveId || "").trim();
    if (!h || !id) return "";
    const base = String(origin || "https://fleaber.pt").replace(/\/$/, "");
    return `${base}/fleahub/index.html#/${encodeURIComponent(h).replace(/%2F/gi, "/")}/live?liveId=${encodeURIComponent(id)}`;
  }

  async function fetchHubItems(liveId) {
    if (!liveId) return [];
    const rows = await getJson(
      `${restBase()}/hub_live_items_public?live_id=eq.${encodeURIComponent(liveId)}&select=id,live_id,ref_code,title,photo_url,price,is_active,status,item_kind,clothing_size&order=created_at.asc`,
    );
    return Array.isArray(rows) ? rows : [];
  }

  async function fetchFomo(liveId) {
    if (!liveId) return { ok: false, items: [] };
    try {
      return await postRpc("batata_hub_live_fomo_snapshot", { p_live_id: liveId });
    } catch (e) {
      return { ok: false, error: String(e.message || e), items: [] };
    }
  }

  async function fetchItemStock(liveItemId) {
    if (!liveItemId) return null;
    try {
      const h = await stockHeaders();
      const res = await fetch(`${restBase()}/rpc/batata_live_item_stock`, {
        method: "POST",
        headers: h,
        body: JSON.stringify({ p_live_item_id: liveItemId }),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok || !data || data.ok === false) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  async function resolveMux(liveId) {
    if (!liveId) return null;
    try {
      let h = headers();
      try {
        const S = global.FleaberStudioSeller;
        if (S?.refreshIfNeeded) {
          const s = await S.refreshIfNeeded();
          if (s?.accessToken) {
            const key = env().anonKey || "";
            h = {
              apikey: key,
              Authorization: `Bearer ${s.accessToken}`,
              "Content-Type": "application/json",
            };
          }
        }
      } catch (_) {}
      const res = await fetch(`${fnBase()}/resolve-mux-playback`, {
        method: "POST",
        headers: h,
        body: JSON.stringify({ live_id: liveId }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.error) return { ok: false, error: data.error || `http_${res.status}` };
      return {
        ok: true,
        playbackId: data.playback_id || null,
        playbackUrl: data.playback_url || null,
        isLive: !!data.is_live,
        source: data.source || null,
      };
    } catch (e) {
      return { ok: false, error: String(e.message || e) };
    }
  }

  function muxHlsUrl(playbackId, isLive) {
    const id = String(playbackId || "").trim();
    if (!id) return "";
    const base = `https://stream.mux.com/${id}.m3u8`;
    return isLive ? `${base}?reduced_latency=true&max_resolution=1080p` : base;
  }

  function muxThumbUrl(playbackId) {
    const id = String(playbackId || "").trim();
    if (!id) return "";
    return `https://image.mux.com/${id}/thumbnail.jpg?time=1&width=640`;
  }

  /**
   * Merge pairing catalog + hub items + fomo + optional stock into product cards.
   */
  function mergeProducts({ catalog, hubItems, fomo, stocksById }) {
    const byId = new Map();
    const fomoItems = Array.isArray(fomo?.items) ? fomo.items : [];
    const fomoById = new Map(
      fomoItems.map((it) => [String(it.live_item_id || ""), it]),
    );

    (hubItems || []).forEach((h) => {
      const id = String(h.id || "");
      byId.set(id, {
        liveItemId: id,
        refCode: h.ref_code || null,
        title: h.title || h.ref_code || "Artigo",
        photoUrl: h.photo_url || null,
        price: typeof h.price === "number" ? h.price : Number(h.price) || null,
        isActive: !!h.is_active,
        status: h.status || null,
        availableQty: null,
        reservedQty: null,
        pendingQueue: null,
        soldQty: null,
        pendingBagQty: null,
        acceptedQty: null,
        totalQty: null,
        blockedQty: null,
        stockOk: false,
      });
    });

    // Pairing catalog may lack UUID — match by ref
    (catalog || []).forEach((c) => {
      const ref = (c.ref_code || c.ref || "").toString();
      let row = [...byId.values()].find(
        (p) =>
          p.refCode &&
          ref &&
          p.refCode.replace(/^#/, "").toUpperCase() ===
            ref.replace(/^#/, "").toUpperCase(),
      );
      if (!row && c.live_item_id) {
        row = byId.get(String(c.live_item_id));
      }
      if (!row) {
        const id = String(c.live_item_id || `ref:${ref}` || Math.random());
        row = {
          liveItemId: c.live_item_id || null,
          refCode: ref || null,
          title: c.title || ref || "Artigo",
          photoUrl: null,
          price: null,
          isActive: !!c.is_active,
          status: null,
          // Nunca usar quantity do catálogo de emparelhamento como «Stock» UI.
          availableQty: null,
          reservedQty: null,
          pendingQueue: null,
          soldQty: null,
          pendingBagQty: null,
          acceptedQty: null,
          totalQty: null,
          blockedQty: null,
          stockOk: false,
        };
        byId.set(id, row);
      } else if (c.is_active) {
        row.isActive = true;
      }
    });

    fomoById.forEach((f, id) => {
      let row = byId.get(id);
      if (!row) {
        row = {
          liveItemId: id,
          refCode: null,
          title: "Artigo",
          photoUrl: null,
          price: null,
          isActive: false,
          status: f.status || null,
          availableQty: null,
          reservedQty: null,
          pendingQueue: null,
          soldQty: null,
          pendingBagQty: null,
          acceptedQty: null,
          totalQty: null,
          blockedQty: null,
          stockOk: false,
        };
        byId.set(id, row);
      }
      row.availableQty =
        f.available_qty != null ? Number(f.available_qty) : row.availableQty;
      row.reservedQty =
        f.display_reserved_qty != null
          ? Number(f.display_reserved_qty)
          : row.reservedQty;
      row.pendingQueue =
        f.pending_queue_count != null
          ? Number(f.pending_queue_count)
          : row.pendingQueue;
      row.status = f.status || row.status;
      row.isLastUnit = !!f.is_last_unit;
    });

    Object.entries(stocksById || {}).forEach(([id, st]) => {
      const row = byId.get(id);
      if (!row || !st) return;
      row.stockOk = true;
      row.availableQty =
        st.available_qty != null ? Number(st.available_qty) : row.availableQty;
      row.soldQty =
        st.sold_converted_qty != null ? Number(st.sold_converted_qty) : null;
      row.pendingBagQty =
        st.pending_bag_qty != null ? Number(st.pending_bag_qty) : null;
      row.acceptedQty =
        st.reserved_accepted_qty != null
          ? Number(st.reserved_accepted_qty)
          : null;
      row.reservedQty =
        (row.pendingBagQty || 0) + (row.acceptedQty || 0) || row.reservedQty;
      if (st.total_qty != null) row.totalQty = Number(st.total_qty);
      if (st.blocked_qty != null) row.blockedQty = Number(st.blocked_qty);
      if (st.live_item_price != null || st.price != null) {
        row.price = Number(st.live_item_price ?? st.price);
      }
    });

    return [...byId.values()].sort((a, b) => {
      if (a.isActive !== b.isActive) return a.isActive ? -1 : 1;
      return String(a.refCode || "").localeCompare(String(b.refCode || ""));
    });
  }

  function computeMetrics({ hubLive, fomo, products, journal, frozenDurationSec, queueRows }) {
    const metrics = {
      viewersFleaber: null,
      durationSec: null,
      productsCount: products?.length || 0,
      pendingQueueTotal: 0,
      reservedTotal: 0,
      availableTotal: 0,
      soldTotal: null,
      gmvEur: null,
      pendingBagTotal: null,
      acceptedPayTotal: null,
      lowStockCount: 0,
      fbReservesOk: 0,
      fbReservesFail: 0,
      liveActive: isHubLiveActive(hubLive),
      sources: [],
    };

    if (hubLive?.viewer_count != null) {
      metrics.viewersFleaber = Number(hubLive.viewer_count) || 0;
      metrics.sources.push("hub_lives_public.viewer_count");
    } else if (fomo?.viewer_count != null) {
      metrics.viewersFleaber = Number(fomo.viewer_count) || 0;
      metrics.sources.push("fomo.viewer_count");
    }

    const dur = computeDurationSec(hubLive, frozenDurationSec);
    if (dur != null) {
      metrics.durationSec = dur;
      metrics.sources.push(
        frozenDurationSec != null
          ? "duration_frozen"
          : "hub_lives_public.went_live_at",
      );
    }

    let soldSum = 0;
    let soldKnown = false;
    let gmv = 0;
    let gmvKnown = false;
    let pendingBag = 0;
    let accepted = 0;
    let payKnown = false;

    (products || []).forEach((p) => {
      metrics.pendingQueueTotal += Number(p.pendingQueue || 0);
      metrics.reservedTotal += Number(p.reservedQty || 0);
      if (p.availableQty != null) {
        metrics.availableTotal += Number(p.availableQty);
        if (p.availableQty <= 1) metrics.lowStockCount += 1;
      }
      if (p.stockOk && p.soldQty != null) {
        soldKnown = true;
        soldSum += Number(p.soldQty);
        if (p.price != null && p.price > 0) {
          gmvKnown = true;
          gmv += Number(p.soldQty) * Number(p.price);
        }
      }
      if (p.stockOk) {
        payKnown = true;
        pendingBag += Number(p.pendingBagQty || 0);
        accepted += Number(p.acceptedQty || 0);
      }
    });

    if (soldKnown) metrics.soldTotal = soldSum;
    if (gmvKnown) metrics.gmvEur = Math.round(gmv * 100) / 100;
    if (payKnown) {
      metrics.pendingBagTotal = pendingBag;
      metrics.acceptedPayTotal = accepted;
      metrics.sources.push("batata_live_item_stock");
    }
    if (metrics.pendingQueueTotal > 0 || (products || []).some((p) => p.pendingQueue != null)) {
      metrics.sources.push("batata_hub_live_fomo_snapshot");
    }

    const list = Array.isArray(journal) ? journal : [];
    let journalFail = 0;
    list.forEach((e) => {
      const intent = String(e.intent || "").toLowerCase();
      const action = String(e.action || "").toLowerCase();
      if (intent === "reserve" || /created|superseded/.test(action)) {
        if (e.ok === false) journalFail += 1;
      }
    });
    metrics.fbReservesFail = journalFail;

    // Contagem operacional = No saco + Aceites a pagar (não canceladas)
    const Act = global.FleaberStudioActivity;
    if (Act?.activeFaceReserveCount && Array.isArray(queueRows) && queueRows.length) {
      metrics.fbReservesOk = Act.activeFaceReserveCount(queueRows);
      metrics.sources.push("seller_queue_active_face");
    } else if (Act?.canonicalReserveCount) {
      metrics.fbReservesOk = Act.canonicalReserveCount({
        queueRows,
        journal: list,
      });
      metrics.sources.push(
        Array.isArray(queueRows) && queueRows.length
          ? "seller_queue_canonical"
          : "psStepJournal_unique",
      );
    } else {
      list.forEach((e) => {
        const intent = String(e.intent || "").toLowerCase();
        if (intent === "reserve" || /created|superseded/.test(String(e.action || ""))) {
          if (e.ok === true) metrics.fbReservesOk += 1;
        }
      });
      if (list.length) metrics.sources.push("psStepJournal");
    }

    return metrics;
  }

  async function fetchLiveMessages(liveId, limit = 60) {
    if (!liveId) return [];
    const lim = Math.max(1, Math.min(Number(limit) || 60, 100));
    try {
      const rows = await getJson(
        `${restBase()}/hub_live_messages_public?live_id=eq.${encodeURIComponent(liveId)}&select=id,live_id,kind,body,sender_label,tip_amount,created_at,channel&order=created_at.desc&limit=${lim}`,
      );
      return Array.isArray(rows) ? rows : [];
    } catch (_) {
      return [];
    }
  }

  async function loadLiveBundle(liveId, catalog) {
    const [hubLive, hubItems, fomo, mux, liveMessages] = await Promise.all([
      fetchHubLive(liveId).catch(() => null),
      fetchHubItems(liveId).catch(() => []),
      fetchFomo(liveId),
      resolveMux(liveId),
      fetchLiveMessages(liveId, 60),
    ]);

    const fomoItems = Array.isArray(fomo?.items) ? fomo.items : [];
    const ids = [
      ...new Set([
        ...hubItems.map((h) => h.id).filter(Boolean),
        ...fomoItems.map((f) => f.live_item_id).filter(Boolean),
      ]),
    ].slice(0, 24);

    const stocksById = {};
    await Promise.all(
      ids.map(async (id) => {
        const st = await fetchItemStock(id);
        if (st) stocksById[id] = st;
      }),
    );

    const products = mergeProducts({
      catalog: catalog || [],
      hubItems,
      fomo,
      stocksById,
    });

    let playbackUrl = mux?.playbackUrl || null;
    let playbackId = mux?.playbackId || null;
    let isLive = !!mux?.isLive;
    if (!playbackUrl) {
      playbackId =
        hubLive?.mux_playback_id || hubLive?.mux_vod_playback_id || null;
      isLive = !!hubLive?.mux_playback_id && hubLive?.status === "live";
      if (playbackId) playbackUrl = muxHlsUrl(playbackId, isLive);
    }

    return {
      hubLive,
      hubItems,
      fomo,
      mux,
      products,
      liveMessages: Array.isArray(liveMessages) ? liveMessages : [],
      playback: {
        ok: !!(playbackUrl || playbackId),
        playbackId,
        playbackUrl,
        isLive,
        thumbUrl: playbackId ? muxThumbUrl(playbackId) : "",
        error: mux?.ok === false ? mux.error : null,
      },
    };
  }

  global.FleaberStudioHub = {
    fetchHubLive,
    fetchHubItems,
    fetchFomo,
    fetchItemStock,
    fetchLiveMessages,
    resolveMux,
    fetchSellerLives,
    fetchSellerProfile,
    buildHubLiveWebUrl,
    isHubLiveActive,
    computeDurationSec,
    buildHistoryEntry,
    mergeHistoryLists,
    muxHlsUrl,
    muxThumbUrl,
    mergeProducts,
    computeMetrics,
    loadLiveBundle,
  };
})(typeof window !== "undefined" ? window : globalThis);
