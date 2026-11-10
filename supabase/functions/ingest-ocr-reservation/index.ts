import { buildCorsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type IngestBody = {
  live_id?: string;
  ref_number?: number;
  ref_slug?: string;
  public_slot?: number;
  requested_qty?: number;
  title_hint?: string;
  external_display_name?: string;
  external_buyer_ref?: string;
  ocr_raw_line?: string;
  ocr_line_hash?: string;
  detected_at?: string;
  chat_sequence?: number;
  avatar_phash?: string;
  ingest_confidence?: number;
  ocr_confidence?: number;
  parser_confidence?: number;
  identity_confidence?: number;
  parser_intent?: string;
  device_id?: string;
  force_needs_review?: boolean;
  /** Official Face/Graph comment id when available (Phase 6 idempotency). */
  comment_id?: string;
  /** ocr | extension | graph — metadata only; never invents IDs. */
  event_channel?: string;
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

/** E74/E75 bridge: grava ledger após OCR OK. Nunca falha o OCR; devolve estado PS separado. */
async function recordPsLedgerAfterOcr(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  body: IngestBody,
  liveId: string,
  result: Record<string, unknown>,
): Promise<{ ok: boolean; skipped?: boolean; error?: string; deduped?: boolean }> {
  try {
    const reservationId =
      (result["reservation_id"] as string | undefined) ??
      (result["request_id"] as string | undefined) ??
      null;
    const sellerId = (result["seller_id"] as string | undefined) ?? null;
    if (!sellerId) {
      return { ok: false, skipped: true, error: "missing_seller_id" };
    }
    const { data, error } = await supabase.rpc(
      "batata_commerce_ps_after_ocr_ingest",
      {
        p_live_id: liveId,
        p_seller_id: sellerId,
        p_ocr_line_hash: (body.ocr_line_hash ?? "").trim() || null,
        p_comment_id: (body.comment_id ?? "").trim() || null,
        p_reservation_id: reservationId,
        p_outcome: String(result["action"] ?? result["status"] ?? "ocr_ok"),
        p_result: result,
      },
    );
    if (error) {
      console.error("ps_ledger_bridge_rpc_error", error.message ?? "rpc_error");
      return { ok: false, error: "ps_ledger_rpc_failed" };
    }
    const row = (data ?? {}) as Record<string, unknown>;
    if (row.ok === false) {
      console.error("ps_ledger_bridge_rejected", String(row.error ?? "rejected"));
      return { ok: false, error: String(row.error ?? "ps_ledger_rejected") };
    }
    return {
      ok: true,
      deduped: row.deduped === true,
    };
  } catch (e) {
    // Compat: se RPC ausente — OCR continua; PS não é sucesso.
    const msg = e instanceof Error ? e.message : "ps_ledger_exception";
    console.error("ps_ledger_bridge_exception", msg.slice(0, 120));
    return { ok: false, error: "ps_ledger_exception" };
  }
}

/** Append-only step log (não falha o ingest se a tabela ainda não existir). */
async function writeIngestAudit(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  body: IngestBody,
  liveId: string,
  result: Record<string, unknown>,
  httpHint?: { ok?: boolean; error?: string },
) {
  try {
    const ok = httpHint?.ok ?? result.ok !== false;
    await supabase.from("ps_ingest_audit").insert({
      live_id: liveId,
      seller_id: (result.seller_id as string) || null,
      chat_sequence: body.chat_sequence ?? null,
      ocr_line_hash: (body.ocr_line_hash ?? "").trim() || null,
      ocr_raw_line: (body.ocr_raw_line ?? "").trim() || null,
      external_display_name: (body.external_display_name ?? "").trim() || null,
      external_buyer_ref: (body.external_buyer_ref ?? "").trim() || null,
      parser_intent: (body.parser_intent ?? "").trim() || null,
      requested_qty: body.requested_qty ?? null,
      ref_slug_in: (body.ref_slug ?? "").trim() || null,
      public_slot_in: body.public_slot ?? null,
      ok,
      action: (result.action as string) || null,
      reservation_id: (result.reservation_id as string) ||
        (result.id as string) ||
        null,
      resolved_ref_slug: (result.resolved_ref_slug as string) ||
        (result.ref_slug as string) ||
        null,
      qty_after: result.requested_qty != null
        ? Number(result.requested_qty)
        : null,
      ingest_status: (result.ingest_status as string) || null,
      error: httpHint?.error ||
        (result.error != null ? String(result.error) : null),
      result_meta: result,
      device_id: (body.device_id ?? "").trim() || null,
    });
  } catch (_) {
    /* tabela ainda não deployada — ignorar */
  }
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ ok: false, error: "server_config" }, 500);
    }

    const deviceToken =
      req.headers.get("x-device-token")?.trim() ??
      req.headers.get("X-Device-Token")?.trim() ??
      "";

    if (!deviceToken) {
      return jsonResponse({ ok: false, error: "missing_device_token" }, 401);
    }

    const body = (await req.json().catch(() => ({}))) as IngestBody;
    const liveId = (body.live_id ?? "").trim();
    if (!liveId) {
      return jsonResponse({ ok: false, error: "missing_live_id" }, 400);
    }

    const lineHash = (body.ocr_line_hash ?? "").trim();
    if (lineHash.length < 8) {
      return jsonResponse({ ok: false, error: "missing_line_hash" }, 400);
    }

    const detectedAt = (body.detected_at ?? "").trim();
    if (!detectedAt) {
      return jsonResponse({ ok: false, error: "missing_detected_at" }, 400);
    }

    const refSlug = (body.ref_slug ?? "").trim();
    const refNumber = Number(body.ref_number ?? 0);
    const useV2 = refSlug.length > 0 ||
      body.public_slot != null ||
      body.requested_qty != null && body.requested_qty !== 1 ||
      body.ocr_confidence != null;

    if (!useV2) {
      if (!Number.isFinite(refNumber) || refNumber < 1 || refNumber > 999) {
        return jsonResponse({ ok: false, error: "invalid_ref_number" }, 400);
      }
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    if (useV2) {
      const { data, error } = await supabase.rpc(
        "batata_ingest_ocr_reservation_v2",
        {
          p_device_token: deviceToken,
          p_live_id: liveId,
          p_external_display_name: (body.external_display_name ?? "").trim(),
          p_external_buyer_ref: (body.external_buyer_ref ?? "").trim(),
          p_ocr_raw_line: (body.ocr_raw_line ?? "").trim(),
          p_ocr_line_hash: lineHash,
          p_detected_at: detectedAt,
          p_ref_slug: refSlug || null,
          p_public_slot: body.public_slot ?? null,
          p_ref_number: Number.isFinite(refNumber) && refNumber >= 1
            ? refNumber
            : null,
          p_requested_qty: body.requested_qty ?? 1,
          p_title_hint: (body.title_hint ?? "").trim() || null,
          p_chat_sequence: body.chat_sequence ?? null,
          p_avatar_phash: (body.avatar_phash ?? "").trim() || null,
          p_ocr_confidence: body.ocr_confidence ?? body.ingest_confidence ?? null,
          p_parser_confidence: body.parser_confidence ?? null,
          p_identity_confidence: body.identity_confidence ?? null,
          p_parser_intent: (body.parser_intent ?? "").trim() || null,
          p_device_id: (body.device_id ?? "").trim() || null,
          p_force_needs_review: body.force_needs_review ?? false,
          p_comment_id: (body.comment_id ?? "").trim() || null,
          p_event_channel: (body.event_channel ?? "").trim() ||
            ((body.comment_id ?? "").trim() ? "extension" : "ocr"),
        },
      );

      if (error) {
        await writeIngestAudit(supabase, body, liveId, {
          ok: false,
          error: error.message,
          code: error.code,
        }, { ok: false, error: error.message });
        return jsonResponse(
          { ok: false, error: error.message, code: error.code },
          500,
        );
      }

      const result = (data ?? {}) as Record<string, unknown>;
      if (result.duplicate === true) {
        await writeIngestAudit(supabase, body, liveId, result, { ok: true });
        return jsonResponse({ ...result, ok: true }, 409);
      }
      if (result.ok === false) {
        const err = String(result.error ?? "ingest_failed");
        const status = err === "invalid_token" ? 401 : 400;
        await writeIngestAudit(supabase, body, liveId, result, {
          ok: false,
          error: err,
        });
        return jsonResponse(result, status);
      }
      await writeIngestAudit(supabase, body, liveId, result, { ok: true });
      // E74/E75: ledger bridge — NÃO substitui OCR v2; falha do ledger não quebra ingest.
      const psLedger = await recordPsLedgerAfterOcr(
        supabase,
        body,
        liveId,
        result,
      );
      return jsonResponse({ ...result, ps_ledger: psLedger }, 200);
    }

    const { data, error } = await supabase.rpc("batata_ingest_ocr_reservation", {
      p_device_token: deviceToken,
      p_live_id: liveId,
      p_ref_number: refNumber,
      p_external_display_name: (body.external_display_name ?? "").trim(),
      p_external_buyer_ref: (body.external_buyer_ref ?? "").trim(),
      p_ocr_raw_line: (body.ocr_raw_line ?? "").trim(),
      p_ocr_line_hash: lineHash,
      p_detected_at: detectedAt,
      p_chat_sequence: body.chat_sequence ?? null,
      p_avatar_phash: (body.avatar_phash ?? "").trim() || null,
      p_ingest_confidence: body.ingest_confidence ?? null,
    });

    if (error) {
      await writeIngestAudit(supabase, body, liveId, {
        ok: false,
        error: error.message,
        code: error.code,
      }, { ok: false, error: error.message });
      return jsonResponse(
        { ok: false, error: error.message, code: error.code },
        500,
      );
    }

    const result = (data ?? {}) as Record<string, unknown>;
    if (result.duplicate === true) {
      await writeIngestAudit(supabase, body, liveId, result, { ok: true });
      return jsonResponse({ ...result, ok: true }, 409);
    }
    if (result.ok === false) {
      const err = String(result.error ?? "ingest_failed");
      const status = err === "invalid_token" ? 401 : 400;
      await writeIngestAudit(supabase, body, liveId, result, {
        ok: false,
        error: err,
      });
      return jsonResponse(result, status);
    }

    await writeIngestAudit(supabase, body, liveId, result, { ok: true });
    const psLedger = await recordPsLedgerAfterOcr(
      supabase,
      body,
      liveId,
      result,
    );
    return jsonResponse({ ...result, ps_ledger: psLedger }, 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return jsonResponse({ ok: false, error: msg }, 500);
  }
});
