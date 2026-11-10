/**
 * Meta Page webhooks — verification + signed ingest (Phase 8).
 *
 * URL: https://<project>.supabase.co/functions/v1/meta-webhook
 * Secrets: META_APP_SECRET | FACEBOOK_APP_SECRET, META_WEBHOOK_VERIFY_TOKEN
 *
 * Does NOT mutate stock directly — delegates to batata_ingest_ocr_reservation_v2 (graph channel).
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  metaAppSecretFromEnv,
  metaWebhookVerifyTokenFromEnv,
  verifyMetaWebhookSignature,
} from "../_shared/meta_webhook_crypto.ts";
import {
  buildGraphIngestRpc,
  extractFeedCommentEvents,
  fetchLiveCatalogForGraph,
} from "../_shared/meta_graph_ingest.ts";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    const expected = metaWebhookVerifyTokenFromEnv();
    if (mode === "subscribe" && token && expected && token === expected && challenge) {
      return new Response(challenge, {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      });
    }
    return json({ ok: false, error: "verify_failed" }, 403);
  }

  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const appSecret = metaAppSecretFromEnv();
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!appSecret || !supabaseUrl || !serviceRole) {
    console.error("meta-webhook missing config (secret/url/service role)");
    return json({ ok: false, error: "config" }, 500);
  }

  const rawBody = await req.text();
  const sig = req.headers.get("X-Hub-Signature-256") ??
    req.headers.get("x-hub-signature-256");
  const sigOk = await verifyMetaWebhookSignature(rawBody, sig, appSecret);
  if (!sigOk) {
    return json({ ok: false, error: "invalid_signature" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false },
  });

  const events = extractFeedCommentEvents(body);
  const results: Record<string, unknown>[] = [];
  /** Cache catalog per live_id within this webhook delivery batch. */
  const catalogByLive = new Map<string, Awaited<ReturnType<typeof fetchLiveCatalogForGraph>>>();

  for (const ev of events) {
    if (ev.verb !== "add" && ev.verb !== "edited") {
      results.push({ delivery_key: ev.deliveryKey, skipped: "verb_" + ev.verb });
      continue;
    }

    const { data: claim, error: claimErr } = await supabase.rpc(
      "batata_meta_webhook_claim_delivery",
      {
        p_delivery_key: ev.deliveryKey,
        p_page_id: ev.pageId,
        p_payload: ev,
      },
    );
    if (claimErr) {
      results.push({
        delivery_key: ev.deliveryKey,
        error: claimErr.message,
      });
      continue;
    }
    const claimObj = (claim ?? {}) as Record<string, unknown>;
    if (claimObj.duplicate === true) {
      results.push({
        delivery_key: ev.deliveryKey,
        duplicate: true,
      });
      continue;
    }
    if (claimObj.ok === false) {
      results.push({
        delivery_key: ev.deliveryKey,
        error: claimObj.error ?? "claim_failed",
      });
      continue;
    }

    const liveId = String(claimObj.live_id ?? "").trim();
    if (!liveId) {
      await supabase.rpc("batata_meta_webhook_finish_delivery", {
        p_delivery_key: ev.deliveryKey,
        p_status: "skipped",
        p_result: { error: "no_live_binding" },
      });
      results.push({
        delivery_key: ev.deliveryKey,
        skipped: "no_live_binding",
      });
      continue;
    }

    let catalog = catalogByLive.get(liveId);
    if (!catalog) {
      catalog = await fetchLiveCatalogForGraph(supabase, liveId);
      catalogByLive.set(liveId, catalog);
    }

    const built = buildGraphIngestRpc({
      pageId: ev.pageId,
      liveId,
      commentId: ev.commentId,
      message: ev.message,
      fromId: ev.fromId,
      fromName: ev.fromName,
      createdTime: ev.createdTime,
      deliveryKey: ev.deliveryKey,
      catalog,
      // CHECK live_reservation_requests_ingest_channel_chk permite 'graph'
      eventChannel: "graph",
    });

    if (built.skipped) {
      await supabase.rpc("batata_meta_webhook_finish_delivery", {
        p_delivery_key: ev.deliveryKey,
        p_status: "skipped",
        p_result: { skipped: built.skipped },
      });
      results.push({ delivery_key: ev.deliveryKey, skipped: built.skipped });
      continue;
    }

    const { data: ingest, error: ingestErr } = await supabase.rpc(
      "batata_ingest_ocr_reservation_v2",
      built.rpc,
    );

    const ingestObj = (ingest ?? {}) as Record<string, unknown>;
    const status = ingestErr
      ? "error"
      : ingestObj.duplicate === true
      ? "duplicate"
      : ingestObj.ok === false
      ? "error"
      : "processed";

    await supabase.rpc("batata_meta_webhook_finish_delivery", {
      p_delivery_key: ev.deliveryKey,
      p_status: status,
      p_result: ingestErr
        ? { error: ingestErr.message }
        : ingestObj,
    });

    results.push({
      delivery_key: ev.deliveryKey,
      status,
      ingest: ingestErr ? { error: ingestErr.message } : ingestObj,
    });
  }

  return json({
    ok: true,
    object: body.object ?? null,
    processed: results.length,
    results,
  });
});
