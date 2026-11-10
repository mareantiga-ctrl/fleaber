/**
 * Messenger / Private Reply outbound gate (Phase 8 / 8.1).
 * Default: messaging_enabled=false → no send.
 * Concurrent claim prevents double Private Reply.
 * Ambiguous Meta outcomes mark claim as ambiguous — never free-repeat.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const DEFAULT_GRAPH_VERSION = "v21.0";
const SEND_TIMEOUT_MS = 12_000;

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
    return JSON.parse(raw) as Record<string, string>;
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const auth = req.headers.get("Authorization") ?? "";
  if (!serviceRole || auth !== `Bearer ${serviceRole}`) {
    return json({ ok: false, error: "not_allowed" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  if (!supabaseUrl) {
    return json({ ok: false, error: "config" }, 500);
  }

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const pageId = String(body.page_id ?? "").trim();
  const sellerId = String(body.seller_id ?? "").trim();
  const commentId = String(body.comment_id ?? "").trim();
  const text = String(body.text ?? "").trim();
  const dryRun = body.dry_run === true;
  /** Force claim path without Graph send (staging concurrency tests). */
  const claimOnly = body.claim_only === true;

  if (!pageId || !sellerId || !commentId || (!text && !claimOnly && !dryRun)) {
    return json({ ok: false, error: "missing_params" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false },
  });

  const { data: claimData, error: claimErr } = await supabase.rpc(
    "batata_commerce_messenger_claim_send",
    {
      p_seller_id: sellerId,
      p_page_id: pageId,
      p_comment_id: commentId,
    },
  );

  if (claimErr) {
    return json({ ok: false, error: claimErr.message }, 500);
  }

  const claim = (claimData ?? {}) as Record<string, unknown>;
  if (claim.eligible !== true) {
    return json({
      ok: true,
      sent: false,
      channel: "messenger_external",
      reason: claim.reason ?? "not_eligible",
    });
  }

  if (claim.claim !== true) {
    return json({
      ok: true,
      sent: false,
      channel: "messenger_external",
      duplicate: true,
      reason: claim.reason ?? "claim_denied",
    });
  }

  if (dryRun || claimOnly) {
    await supabase.rpc("batata_commerce_messenger_finish_send", {
      p_page_id: pageId,
      p_comment_id: commentId,
      p_status: "skipped",
      p_error: dryRun ? "dry_run" : "claim_only",
    });
    await supabase.rpc("batata_commerce_messenger_log_outbound", {
      p_seller_id: sellerId,
      p_page_id: pageId,
      p_comment_id: commentId,
      p_eligible: true,
      p_sent: false,
      p_skip_reason: dryRun ? "dry_run" : "claim_only",
    });
    return json({
      ok: true,
      sent: false,
      dry_run: dryRun,
      claim_only: claimOnly,
      channel: "messenger_external",
      claimed: true,
    });
  }

  const tokens = pageTokensFromEnv();
  const pageToken = tokens[pageId];
  if (!pageToken) {
    await supabase.rpc("batata_commerce_messenger_finish_send", {
      p_page_id: pageId,
      p_comment_id: commentId,
      p_status: "failed",
      p_error: "no_page_token",
    });
    await supabase.rpc("batata_commerce_messenger_log_outbound", {
      p_seller_id: sellerId,
      p_page_id: pageId,
      p_comment_id: commentId,
      p_eligible: true,
      p_sent: false,
      p_skip_reason: "no_page_token",
    });
    return json({
      ok: false,
      error: "not_configured",
      hint: "META_PAGE_ACCESS_TOKENS_JSON",
    }, 503);
  }

  const graphVersion = String(body.graph_version ?? DEFAULT_GRAPH_VERSION).trim();
  const sendUrl =
    `https://graph.facebook.com/${graphVersion}/${pageId}/messages?access_token=${encodeURIComponent(pageToken)}`;

  let sendRes: Response;
  let sendJson: Record<string, unknown> = {};
  try {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), SEND_TIMEOUT_MS);
    try {
      sendRes = await fetch(sendUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          recipient: { comment_id: commentId },
          message: { text },
        }),
        signal: ac.signal,
      });
    } finally {
      clearTimeout(timer);
    }
    sendJson = await sendRes.json().catch(() => ({})) as Record<string, unknown>;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // Timeout / network after possible send → ambiguous (do not free-retry)
    const ambiguous = /abort|timeout|network|fetch/i.test(msg);
    await supabase.rpc("batata_commerce_messenger_finish_send", {
      p_page_id: pageId,
      p_comment_id: commentId,
      p_status: ambiguous ? "ambiguous" : "failed",
      p_error: msg.slice(0, 200),
    });
    await supabase.rpc("batata_commerce_messenger_log_outbound", {
      p_seller_id: sellerId,
      p_page_id: pageId,
      p_comment_id: commentId,
      p_eligible: true,
      p_sent: false,
      p_skip_reason: ambiguous ? "ambiguous_network" : msg.slice(0, 120),
    });
    return json({
      ok: false,
      error: ambiguous ? "ambiguous_outcome" : "network_failed",
      detail: msg,
    }, 502);
  }

  const sent = sendRes.ok;
  // Ambiguous HTTP: 2xx without message_id, or 5xx after possible accept
  const messageId = String(
    (sendJson as { message_id?: string }).message_id ??
      ((sendJson as { messages?: Array<{ id?: string }> }).messages?.[0]?.id ??
        ""),
  ).trim();
  const ambiguousHttp = sent && !messageId;
  const finishStatus = sent
    ? (ambiguousHttp ? "ambiguous" : "sent")
    : (sendRes.status >= 500 ? "ambiguous" : "failed");

  await supabase.rpc("batata_commerce_messenger_finish_send", {
    p_page_id: pageId,
    p_comment_id: commentId,
    p_status: finishStatus,
    p_error: sent
      ? (ambiguousHttp ? "missing_message_id" : null)
      : String(
        (sendJson.error as Record<string, unknown>)?.message ?? sendRes.statusText,
      ),
  });

  await supabase.rpc("batata_commerce_messenger_log_outbound", {
    p_seller_id: sellerId,
    p_page_id: pageId,
    p_comment_id: commentId,
    p_eligible: true,
    p_sent: finishStatus === "sent",
    p_skip_reason: finishStatus === "sent"
      ? null
      : finishStatus,
  });

  if (finishStatus !== "sent") {
    return json({
      ok: false,
      error: finishStatus === "ambiguous" ? "ambiguous_outcome" : "send_failed",
      graph: sendJson,
    }, 502);
  }

  return json({
    ok: true,
    sent: true,
    channel: "messenger_external",
    graph: sendJson,
  });
});
