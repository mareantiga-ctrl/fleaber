/**
 * Via isolada: comentários de publicação normal (Page post) → ingest Fleaber.
 * NÃO substitui o fluxo Live Video (meta-graph-poll / commerce_meta_live_video_bindings).
 * Sem tokens em logs — URLs redigidas.
 */

/**
 * @param {unknown} raw
 * @returns {{ page_id: string, meta_post_id: string, live_id: string }[]}
 */
export function parsePostLiveBindings(raw) {
  if (raw == null || raw === "") return [];
  let arr = raw;
  if (typeof raw === "string") {
    try {
      arr = JSON.parse(raw);
    } catch {
      return [];
    }
  }
  if (!Array.isArray(arr)) return [];
  const out = [];
  for (const row of arr) {
    if (!row || typeof row !== "object") continue;
    const page_id = String(row.page_id ?? row.pageId ?? "").trim();
    const meta_post_id = String(
      row.meta_post_id ?? row.metaPostId ?? row.post_id ?? row.postId ?? "",
    ).trim();
    const live_id = String(row.live_id ?? row.liveId ?? "").trim();
    if (page_id && meta_post_id && live_id) {
      out.push({ page_id, meta_post_id, live_id });
    }
  }
  return out;
}

/**
 * Associação explícita post ↔ directo (pedido ou allowlist de env).
 */
export function resolveExplicitPostLiveAssociation(opts) {
  const pageId = String(opts.pageId ?? "").trim();
  const metaPostId = String(opts.metaPostId ?? "").trim();
  const liveId = String(opts.liveId ?? "").trim();
  if (!pageId || !metaPostId || !liveId) {
    return { ok: false, error: "missing_params" };
  }

  const allowlist = Array.isArray(opts.allowlist) ? opts.allowlist : [];
  if (allowlist.length > 0) {
    const hit = allowlist.find(
      (b) =>
        b.page_id === pageId &&
        b.meta_post_id === metaPostId &&
        b.live_id === liveId,
    );
    if (!hit) {
      return { ok: false, error: "post_binding_not_allowlisted" };
    }
    return {
      ok: true,
      page_id: pageId,
      meta_post_id: metaPostId,
      live_id: liveId,
      source: "allowlist",
    };
  }

  if (opts.explicitPostBinding !== true) {
    return {
      ok: false,
      error: "explicit_post_binding_required",
      hint:
        "Pass explicit_post_binding:true or set META_POST_INGEST_BINDINGS_JSON",
    };
  }

  return {
    ok: true,
    page_id: pageId,
    meta_post_id: metaPostId,
    live_id: liveId,
    source: "request",
  };
}

/**
 * Graph comments URL for a Page post (not Live Video).
 * Token only in returned `url` — use `urlRedacted` for logs/responses.
 */
export function buildPagePostCommentsUrl(opts) {
  const version = String(opts.graphVersion ?? "v21.0").trim() || "v21.0";
  const postId = String(opts.metaPostId ?? "").trim();
  const token = String(opts.pageAccessToken ?? "").trim();
  const limit = Math.min(Math.max(Number(opts.limit) || 25, 1), 50);
  if (!postId || !token) {
    return { ok: false, error: "missing_post_or_token" };
  }
  const base =
    `https://graph.facebook.com/${version}/${encodeURIComponent(postId)}/comments` +
    `?order=reverse_chronological&limit=${limit}&fields=id,message,from,created_time`;
  return {
    ok: true,
    url: `${base}&access_token=${encodeURIComponent(token)}`,
    urlRedacted: `${base}&access_token=REDACTED`,
  };
}

/** Strip accidental token leakage from Graph error strings. */
export function redactSecrets(text) {
  return String(text ?? "")
    .replace(/access_token=[^&\s"']+/gi, "access_token=REDACTED")
    .replace(/EAA[A-Za-z0-9]+/g, "REDACTED_TOKEN");
}

/**
 * @param {unknown} graphJson
 */
export function normalizeGraphPostComments(graphJson) {
  const data =
    graphJson && typeof graphJson === "object" ? graphJson.data : null;
  const rows = Array.isArray(data) ? data : [];
  const out = [];
  for (const c of rows) {
    if (!c || typeof c !== "object") continue;
    const commentId = String(c.id ?? "").trim();
    const message = String(c.message ?? "").trim();
    const from = c.from && typeof c.from === "object" ? c.from : {};
    const fromId = String(from.id ?? "").trim();
    const fromName = String(from.name ?? "").trim();
    const createdTime = String(c.created_time ?? "").trim();
    if (!commentId) continue;
    out.push({ commentId, message, fromId, fromName, createdTime });
  }
  return out;
}

/** Filtra por comment_id exacto (teste pontual) se pedido. */
export function filterCommentsById(comments, commentIdFilter) {
  const want = String(commentIdFilter ?? "").trim();
  if (!want) return comments;
  return comments.filter((c) => c.commentId === want);
}
