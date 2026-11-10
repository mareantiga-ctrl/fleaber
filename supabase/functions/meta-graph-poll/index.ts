/**
 * Graph API polling fallback for Live Video comments (Phase 8 / 8.1).
 * Validates page↔seller↔live↔video binding BEFORE calling Graph.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  buildGraphIngestRpc,
  fetchLiveCatalogForGraph,
} from "../_shared/meta_graph_ingest.ts";

const DEFAULT_GRAPH_VERSION = "v21.0";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function pageTokensFromEnv(): Record<string, string> {
  const raw = (Deno.env.get("META_PAGE_ACCESS_TOKENS_JSON") ?? "").trim();
  if (!raw) return {};
  try {
    const o = JSON.parse(raw) as Record<string, string>;
    return o ?? {};
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const invokeSecret = (Deno.env.get("META_POST_INGEST_INVOKE_SECRET") ?? "")
    .trim();
  const allowed =
    (bearer.length > 0 && serviceRole.length > 0 && bearer === serviceRole) ||
    (bearer.length > 0 && invokeSecret.length > 0 && bearer === invokeSecret);
  if (!allowed) {
    return json({ ok: false, error: "not_allowed" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  if (!supabaseUrl) {
    return json({ ok: false, error: "config" }, 500);
  }
  if (!serviceRole) {
    return json({ ok: false, error: "config" }, 500);
  }

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const pageId = String(body.page_id ?? "").trim();
  const liveId = String(body.live_id ?? "").trim();
  const videoId = String(body.meta_live_video_id ?? "").trim();
  const sellerHint = String(body.seller_id ?? "").trim() || null;
  const limit = Math.min(Number(body.limit ?? 25) || 25, 50);
  const graphVersion = String(body.graph_version ?? DEFAULT_GRAPH_VERSION).trim();

  if (!pageId || !liveId || !videoId) {
    return json({ ok: false, error: "missing_params" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false },
  });

  // Phase 8.1: reject forged ID combos before Graph call
  const { data: bindData, error: bindErr } = await supabase.rpc(
    "batata_meta_assert_poll_binding",
    {
      p_page_id: pageId,
      p_live_id: liveId,
      p_meta_live_video_id: videoId,
      p_seller_id: sellerHint,
    },
  );
  if (bindErr) {
    return json({ ok: false, error: bindErr.message }, 500);
  }
  const bind = (bindData ?? {}) as Record<string, unknown>;
  if (bind.ok !== true) {
    return json({
      ok: false,
      error: String(bind.error ?? "binding_rejected"),
    }, 403);
  }

  const tokens = pageTokensFromEnv();
  const pageToken = tokens[pageId];
  if (!pageToken) {
    return json({
      ok: false,
      error: "not_configured",
      hint: "META_PAGE_ACCESS_TOKENS_JSON missing page id",
    }, 503);
  }

  const url =
    `https://graph.facebook.com/${graphVersion}/${videoId}/comments?order=reverse_chronological&limit=${limit}&access_token=${encodeURIComponent(pageToken)}`;

  let graphRes: Response;
  try {
    graphRes = await fetch(url);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ ok: false, error: "graph_fetch_failed", detail: msg }, 502);
  }

  const graphJson = await graphRes.json().catch(() => ({})) as Record<
    string,
    unknown
  >;

  if (!graphRes.ok) {
    const err = graphJson.error as Record<string, unknown> | undefined;
    const code = err?.code;
    const message = err?.message ?? graphRes.statusText;
    const status = code === 4 || code === 17 || code === 32 ? 429 : 502;
    return json({
      ok: false,
      error: "graph_error",
      graph_status: graphRes.status,
      graph_code: code,
      message,
    }, status);
  }

  const data = graphJson.data;
  const comments = Array.isArray(data) ? data : [];
  const ingested: Record<string, unknown>[] = [];
  const catalog = await fetchLiveCatalogForGraph(supabase, liveId);

  for (const c of comments) {
    const row = c as Record<string, unknown>;
    const commentId = String(row.id ?? "").trim();
    const message = String(row.message ?? "").trim();
    const from = (row.from ?? {}) as Record<string, unknown>;
    const fromId = String(from.id ?? "").trim();
    const fromName = String(from.name ?? "").trim();
    const createdTime = String(row.created_time ?? "").trim();

    const built = buildGraphIngestRpc({
      pageId,
      liveId,
      commentId,
      message,
      fromId,
      fromName,
      createdTime,
      catalog,
      eventChannel: "graph",
    });
    if (built.skipped) {
      ingested.push({ comment_id: commentId, skipped: built.skipped });
      continue;
    }

    const { data: ingest, error } = await supabase.rpc(
      "batata_ingest_ocr_reservation_v2",
      built.rpc,
    );
    ingested.push({
      comment_id: commentId,
      error: error?.message,
      result: ingest,
    });
  }

  await supabase.rpc("batata_meta_poll_cursor_update", {
    p_page_id: pageId,
    p_live_id: liveId,
    p_meta_live_video_id: videoId,
    p_last_polled_at: new Date().toISOString(),
    p_comment_count: comments.length,
  }).catch(() => null);

  return json({
    ok: true,
    graph_version: graphVersion,
    fetched: comments.length,
    ingested,
    binding: { seller_id: bind.seller_id },
  });
});
