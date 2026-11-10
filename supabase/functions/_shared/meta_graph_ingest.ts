/**
 * Normalise Meta Page feed / live comment payloads → ingest RPC params.
 * Graph API v21+ comment object shapes (Phase 8 / 8.1).
 * Parser is bundled under _shared (no path outside functions/).
 */
import { parseCommentLine } from "./fleaber_ps_parser.js";

export type LiveCatalogItem = {
  ref_code?: string | null;
  ref?: string | null;
  title?: string | null;
  name?: string | null;
};

export type GraphCommentIngestInput = {
  pageId: string;
  liveId: string;
  commentId: string;
  message: string;
  fromId?: string | null;
  fromName?: string | null;
  createdTime?: string | null;
  deliveryKey?: string | null;
  /** Catálogo do directo — obrigatório para aceitar refs bare (123, #123, T10). */
  catalog?: LiveCatalogItem[] | null;
  /**
   * Canal de ingest. Live Video poll/webhook = `graph` (default).
   * Post normal (via isolada) = `graph_post` — não misturar com o fluxo Live.
   */
  eventChannel?: string | null;
};

export type ParsedGraphIngest = {
  rpc: Record<string, unknown>;
  parse: Record<string, unknown> | null;
  skipped?: string;
};

export function buildGraphIngestRpc(input: GraphCommentIngestInput): ParsedGraphIngest {
  const message = (input.message ?? "").trim();
  const commentId = (input.commentId ?? "").trim();
  if (!commentId || commentId.length < 4) {
    return { rpc: {}, parse: null, skipped: "missing_comment_id" };
  }
  if (!message) {
    return { rpc: {}, parse: null, skipped: "empty_message" };
  }

  const catalog = Array.isArray(input.catalog) ? input.catalog : [];
  const parsed = parseCommentLine(message, {
    strictRef: true,
    catalog,
  }) as Record<string, unknown> | null;
  const intent = String(parsed?.intent ?? "unknown");
  const refSlug = (parsed?.refSlug as string | null | undefined) ?? null;
  const qtyRaw = parsed?.quantity ?? parsed?.qty ?? 1;
  const qty = Math.max(1, Math.min(Number(qtyRaw) || 1, 99));
  const fromId = (input.fromId ?? "").trim();
  const buyerRef = fromId ? `fb:${fromId}` : "";
  const parserConf = Number(
    parsed?.parserConfidence ?? parsed?.confidence ?? 0.85,
  );

  const lineHash = `graph_msg:${commentId}`;

  // Prefer canonical ref_code from catalog when matched (e.g. keep #123 if stored that way).
  let pRefSlug: string | null = refSlug;
  if (refSlug && catalog.length) {
    const want = String(refSlug).trim().toUpperCase().replace(/^#/, "");
    const hit = catalog.find((it) => {
      const raw = String(it?.ref_code ?? it?.ref ?? "").trim();
      const norm = raw.toUpperCase().replace(/^#/, "");
      return norm === want;
    });
    if (hit) {
      const canonical = String(hit.ref_code ?? hit.ref ?? "").trim();
      if (canonical) pRefSlug = canonical;
    }
  }

  const rpc: Record<string, unknown> = {
    p_device_token: "",
    p_live_id: input.liveId,
    p_external_display_name: (input.fromName ?? "").trim(),
    p_external_buyer_ref: buyerRef,
    p_ocr_raw_line: message,
    p_ocr_line_hash: lineHash,
    p_detected_at: input.createdTime ?? new Date().toISOString(),
    p_ref_slug: pRefSlug,
    p_public_slot: parsed?.publicSlot ?? null,
    p_ref_number: null,
    p_requested_qty: qty,
    p_title_hint: null,
    p_parser_intent: intent,
    p_comment_id: commentId,
    p_event_channel: (input.eventChannel ?? "graph").trim() || "graph",
    p_meta_page_id: input.pageId,
    p_parser_confidence: parserConf,
    p_identity_confidence: fromId ? 0.95 : 0.5,
    p_ocr_confidence: 0.95,
  };

  return { rpc, parse: parsed };
}

/** Load live_items refs for Graph strict+catalog parse. */
export async function fetchLiveCatalogForGraph(
  // deno-lint-ignore no-explicit-any
  supabase: { from: (t: string) => any },
  liveId: string,
): Promise<LiveCatalogItem[]> {
  const lid = String(liveId ?? "").trim();
  if (!lid) return [];
  const { data, error } = await supabase
    .from("live_items")
    .select("ref_code,title")
    .eq("live_id", lid)
    .limit(500);
  if (error || !Array.isArray(data)) return [];
  return data
    .map((row: Record<string, unknown>) => ({
      ref_code: String(row.ref_code ?? "").trim() || null,
      title: String(row.title ?? "").trim() || null,
    }))
    .filter((r: LiveCatalogItem) => !!(r.ref_code && String(r.ref_code).trim()));
}

/** Extract comment-like entries from Meta Page webhook `entry[].changes[]`. */
export function extractFeedCommentEvents(body: Record<string, unknown>): Array<{
  pageId: string;
  commentId: string;
  message: string;
  verb: string;
  postId?: string;
  fromId?: string;
  fromName?: string;
  createdTime?: string;
  deliveryKey: string;
}> {
  const out: Array<{
    pageId: string;
    commentId: string;
    message: string;
    verb: string;
    postId?: string;
    fromId?: string;
    fromName?: string;
    createdTime?: string;
    deliveryKey: string;
  }> = [];

  const entries = body.entry;
  if (!Array.isArray(entries)) return out;

  for (const entry of entries) {
    const pageId = String((entry as Record<string, unknown>).id ?? "").trim();
    const changes = (entry as Record<string, unknown>).changes;
    if (!pageId || !Array.isArray(changes)) continue;

    for (const ch of changes) {
      const change = ch as Record<string, unknown>;
      const field = String(change.field ?? "");
      if (field !== "feed") continue;
      const value = (change.value ?? {}) as Record<string, unknown>;
      const item = String(value.item ?? "");
      if (item !== "comment") continue;
      const verb = String(value.verb ?? "add");
      const commentId = String(value.comment_id ?? value.commentId ?? "").trim();
      const message = String(value.message ?? "").trim();
      const postId = String(value.post_id ?? value.postId ?? "").trim() || undefined;
      const from = (value.from ?? {}) as Record<string, unknown>;
      const fromId = String(from.id ?? "").trim() || undefined;
      const fromName = String(from.name ?? "").trim() || undefined;
      const createdTime = String(value.created_time ?? "").trim() || undefined;
      const deliveryKey = `feed:${pageId}:${commentId}:${verb}:${String(change.id ?? "")}`;

      if (!commentId) continue;
      out.push({
        pageId,
        commentId,
        message,
        verb,
        postId,
        fromId,
        fromName,
        createdTime,
        deliveryKey,
      });
    }
  }
  return out;
}
