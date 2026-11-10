/**
 * Seller session for Studio ops — reuses Supabase Auth (same as Fleaber app).
 * Does NOT widen PS device-token privileges. No service_role.
 */
(function (global) {
  const STORAGE_KEYS = [
    "sellerAccessToken",
    "sellerRefreshToken",
    "sellerEmail",
    "sellerUserId",
    "sellerExpiresAt",
  ];

  function env() {
    return global.FLEABER_STUDIO_ENV || {};
  }

  function authUrl(path) {
    return `${String(env().supabaseUrl || "").replace(/\/$/, "")}/auth/v1${path}`;
  }

  function restUrl(path) {
    return `${String(env().supabaseUrl || "").replace(/\/$/, "")}/rest/v1${path}`;
  }

  async function storageGet(keys) {
    return new Promise((r) => chrome.storage.local.get(keys, r));
  }

  async function storageSet(obj) {
    return new Promise((r) => chrome.storage.local.set(obj, r));
  }

  async function storageRemove(keys) {
    return new Promise((r) => chrome.storage.local.remove(keys, r));
  }

  async function readStoredSession() {
    const raw = await storageGet(STORAGE_KEYS);
    if (!raw.sellerAccessToken) return null;
    return {
      accessToken: raw.sellerAccessToken,
      refreshToken: raw.sellerRefreshToken || null,
      email: raw.sellerEmail || null,
      userId: raw.sellerUserId || null,
      expiresAt: raw.sellerExpiresAt ? Number(raw.sellerExpiresAt) : 0,
    };
  }

  /** Sessão vendedor com refresh se necessário (persiste entre aberturas do Studio). */
  async function getSession() {
    return refreshIfNeeded();
  }

  async function persistSession(data) {
    const expiresAt =
      Date.now() + (Number(data.expires_in || 3600) - 60) * 1000;
    await storageSet({
      sellerAccessToken: data.access_token,
      sellerRefreshToken: data.refresh_token || null,
      sellerEmail: data.user?.email || null,
      sellerUserId: data.user?.id || null,
      sellerExpiresAt: expiresAt,
    });
    return getSession();
  }

  async function signIn(email, password) {
    const key = env().anonKey || "";
    const res = await fetch(authUrl("/token?grant_type=password"), {
      method: "POST",
      headers: {
        apikey: key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: String(email || "").trim(),
        password: String(password || ""),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      return {
        ok: false,
        error: data.error_description || data.msg || data.error || `http_${res.status}`,
      };
    }
    await persistSession(data);
    return { ok: true, session: await getSession() };
  }

  async function signOut() {
    const s = await getSession();
    const key = env().anonKey || "";
    if (s?.accessToken) {
      try {
        await fetch(authUrl("/logout"), {
          method: "POST",
          headers: {
            apikey: key,
            Authorization: `Bearer ${s.accessToken}`,
          },
        });
      } catch (_) {}
    }
    await storageRemove(STORAGE_KEYS);
    return { ok: true };
  }

  async function refreshIfNeeded() {
    const s = await readStoredSession();
    if (!s?.accessToken) return null;
    if (s.expiresAt && Date.now() < s.expiresAt - 15000) return s;
    if (!s.refreshToken) return s;
    const key = env().anonKey || "";
    const res = await fetch(authUrl("/token?grant_type=refresh_token"), {
      method: "POST",
      headers: {
        apikey: key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ refresh_token: s.refreshToken }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      await storageRemove(STORAGE_KEYS);
      return null;
    }
    return persistSession(data);
  }

  async function authHeaders() {
    const s = await refreshIfNeeded();
    if (!s?.accessToken) return null;
    const key = env().anonKey || "";
    return {
      apikey: key,
      Authorization: `Bearer ${s.accessToken}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    };
  }

  async function rpc(name, body) {
    const h = await authHeaders();
    if (!h) return { ok: false, error: "seller_not_signed_in" };
    const res = await fetch(restUrl(`/rpc/${name}`), {
      method: "POST",
      headers: h,
      body: JSON.stringify(body || {}),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg =
        data.message || data.error || data.hint || `http_${res.status}`;
      return { ok: false, error: String(msg), status: res.status };
    }
    return { ok: true, data };
  }

  /** Same RPC as mobile Studio. */
  async function queueForLive(liveId, includeHistory = true) {
    const out = await rpc("batata_live_reservation_queue_for_live", {
      p_live_id: liveId,
      p_include_history: includeHistory,
    });
    if (!out.ok) return out;
    const rows = Array.isArray(out.data) ? out.data : [];
    return { ok: true, rows };
  }

  async function confirmPs(requestId, action, extra = {}) {
    if (extra.refSlug) {
      return rpc("batata_confirm_ps_reservation_v2", {
        p_request_id: requestId,
        p_action: action,
        p_ref_slug: extra.refSlug,
        ...(extra.publicSlot != null ? { p_public_slot: extra.publicSlot } : {}),
        ...(extra.requestedQty != null
          ? { p_requested_qty: extra.requestedQty }
          : {}),
      });
    }
    return rpc("batata_confirm_ps_reservation", {
      p_request_id: requestId,
      p_action: action,
      ...(extra.refNumber != null ? { p_ref_number: extra.refNumber } : {}),
    });
  }

  async function processReservation(requestId, action, notes) {
    const s = await refreshIfNeeded();
    return rpc("batata_process_live_reservation_request", {
      p_request_id: requestId,
      p_action: action,
      p_processed_by: s?.userId || undefined,
      ...(notes ? { p_notes: notes } : {}),
    });
  }

  function isPsNeedsReview(row) {
    const ingest = String(row.ingest_status || "").toLowerCase();
    const notes = String(row.notes || "").toLowerCase();
    return (
      ingest === "needs_review" ||
      notes.includes("needs_review") ||
      notes.includes("force_needs_review")
    );
  }

  function isWaitlist(row, availableQty) {
    const pos = Number(row.queue_position);
    if (!pos || pos < 1) return false;
    if (availableQty == null) return pos > 1;
    if (availableQty < 1) return true;
    return pos > availableQty;
  }

  function canActPending(row) {
    const st = String(row.status || "").toLowerCase();
    if (st === "rejected" || st === "expired" || st === "converted") return false;
    const notes = String(row.notes || "").toLowerCase();
    if (notes.includes("buyer_cancelled") || notes.includes("cancelado pelo comprador")) {
      return false;
    }
    return st === "pending";
  }

  global.FleaberStudioSeller = {
    getSession,
    signIn,
    signOut,
    refreshIfNeeded,
    queueForLive,
    confirmPs,
    processReservation,
    isPsNeedsReview,
    isWaitlist,
    canActPending,
  };
})(typeof window !== "undefined" ? window : globalThis);
