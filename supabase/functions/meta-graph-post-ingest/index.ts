/**
 * Via ISOLADA de teste: comentÃ¡rios de publicaÃ§Ã£o normal da PÃ¡gina (Graph)
 * â†’ parser (catÃ¡logo do directo) â†’ batata_ingest_ocr_reservation_v2.
 *
 * NÃƒO usa meta_live_video_id / commerce_meta_live_video_bindings.
 * NÃƒO altera o fluxo Live Video (meta-graph-poll / meta-webhook feed+live).
 *
 * Auth: Bearer service_role.
 * Secrets: META_PAGE_ACCESS_TOKENS_JSON (nunca logar), opcional
 * META_POST_INGEST_BINDINGS_JSON allowlist page+post+live.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  buildGraphIngestRpc,
  fetchLiveCatalogForGraph,
} from "../_shared/meta_graph_ingest.ts";
import {
  buildPagePostCommentsUrl,
  filterCommentsById,
  normalizeGraphPostComments,
  parsePostLiveBindings,
  redactSecrets,
  resolveExplicitPostLiveAssociation,
} from "../_shared/meta_graph_post_path.mjs";

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

/**
 * Page ligada + directo do mesmo vendedor (sem inventar video id).
 */
async function assertPageSellerLive(
  // deno-lint-ignore no-explicit-any
  supabase: { from: (t: string) => any },
  pageId: string,
  liveId: string,
  sellerHint: string | null,
): Promise<{ ok: true; seller_id: string } | { ok: false; error: string }> {
  const { data: conn, error: connErr } = await supabase
    .from("commerce_meta_page_connections")
    .select("seller_id,ingest_enabled,revoked_at")
    .eq("page_id", pageId)
    .is("revoked_at", null)
    .eq("ingest_enabled", true)
    .limit(1)
    .maybeSingle();

  if (connErr) {
    return { ok: false, error: "page_lookup_failed" };
  }
  if (!conn?.seller_id) {
    return { ok: false, error: "page_not_linked" };
  }
  const sellerId = String(conn.seller_id);
  if (sellerHint && sellerHint !== sellerId) {
    return { ok: false, error: "seller_page_mismatch" };
  }

  const { data: live, error: liveErr } = await supabase
    .from("lives")
    .select("id,seller_id,vendedor_id,status")
    .eq("id", liveId)
    .maybeSingle();

  if (liveErr || !live?.id) {
    return { ok: false, error: "live_not_found" };
  }
  const liveSeller = String(live.seller_id ?? live.vendedor_id ?? "");
  if (!liveSeller || liveSeller !== sellerId) {
    return { ok: false, error: "live_seller_mismatch" };
  }
  const st = String(live.status ?? "");
  if (st === "ended" || st === "cancelled") {
    return { ok: false, error: "live_not_active" };
  }

  return { ok: true, seller_id: sellerId };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  /** Ops secret dedicado (evita mismatch JWT legado vs runtime). */
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

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const pageId = String(body.page_id ?? "").trim();
  const liveId = String(body.live_id ?? "").trim();
  const metaPostId = String(
    body.meta_post_id ?? body.post_id ?? "",
  ).trim();
  const commentIdFilter = String(body.comment_id ?? "").trim() || null;
  const sellerHint = String(body.seller_id ?? "").trim() || null;
  const limit = Math.min(Number(body.limit ?? 25) || 25, 50);
  const graphVersion = String(body.graph_version ?? DEFAULT_GRAPH_VERSION).trim();
  const explicitPostBinding = body.explicit_post_binding === true;
  const dryRun = body.dry_run === true;

  const allowlist = parsePostLiveBindings(
    Deno.env.get("META_POST_INGEST_BINDINGS_JSON") ?? "",
  );
  const assoc = resolveExplicitPostLiveAssociation({
    pageId,
    metaPostId,
    liveId,
    explicitPostBinding,
    allowlist,
  });
  if (!assoc.ok) {
    return json({
      ok: false,
      error: assoc.error,
      hint: (assoc as { hint?: string }).hint,
    }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false },
  });

  const gate = await assertPageSellerLive(
    supabase,
    pageId,
    liveId,
    sellerHint,
  );
  if (!gate.ok) {
    return json({ ok: false, error: gate.error }, 403);
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

  const builtUrl = buildPagePostCommentsUrl({
    metaPostId,
    pageAccessToken: pageToken,
    graphVersion,
    limit,
  });
  if (!builtUrl.ok || !builtUrl.url) {
    return json({ ok: false, error: builtUrl.error ?? "url_build_failed" }, 400);
  }

  let graphRes: Response;
  try {
    graphRes = await fetch(builtUrl.url);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({
      ok: false,
      error: "graph_fetch_failed",
      detail: redactSecrets(msg),
      graph_url: builtUrl.urlRedacted,
    }, 502);
  }

  const graphJson = await graphRes.json().catch(() => ({})) as Record<
    string,
    unknown
  >;

  if (!graphRes.ok) {
    const err = graphJson.error as Record<string, unknown> | undefined;
    const code = err?.code;
    const message = redactSecrets(String(err?.message ?? graphRes.statusText));
    const status = code === 4 || code === 17 || code === 32 ? 429 : 502;
    return json({
      ok: false,
      error: "graph_error",
      graph_status: graphRes.status,
      graph_code: code,
      message,
      graph_url: builtUrl.urlRedacted,
    }, status);
  }

  let comments = normalizeGraphPostComments(graphJson);
  comments = filterCommentsById(comments, commentIdFilter);

  const catalog = await fetchLiveCatalogForGraph(supabase, liveId);
  const ingested: Record<string, unknown>[] = [];

  for (const c of comments) {
    const built = buildGraphIngestRpc({
      pageId,
      liveId,
      commentId: c.commentId,
      message: c.message,
      fromId: c.fromId,
      fromName: c.fromName,
      createdTime: c.createdTime,
      catalog,
      eventChannel: "graph",
    });
    if (built.skipped) {
      ingested.push({ comment_id: c.commentId, skipped: built.skipped });
      continue;
    }

    if (dryRun) {
      ingested.push({
        comment_id: c.commentId,
        dry_run: true,
        parse_intent: built.parse?.intent ?? null,
        ref_slug: built.rpc.p_ref_slug ?? null,
        qty: built.rpc.p_requested_qty ?? null,
      });
      continue;
    }

    const { data: ingest, error } = await supabase.rpc(
      "batata_ingest_ocr_reservation_v2",
      built.rpc,
    );
    ingested.push({
      comment_id: c.commentId,
      error: error?.message ? redactSecrets(error.message) : undefined,
      result: ingest,
    });
  }

  return json({
    ok: true,
    path: "meta-graph-post-ingest",
    association: {
      page_id: pageId,
      meta_post_id: metaPostId,
      live_id: liveId,
      source: assoc.source,
      seller_id: gate.seller_id,
    },
    catalog_refs: catalog.map((r) => r.ref_code).filter(Boolean),
    graph_url: builtUrl.urlRedacted,
    fetched: Array.isArray(graphJson.data) ? graphJson.data.length : 0,
    matched: comments.length,
    dry_run: dryRun,
    ingested,
  });
});

