/**
 * DPD expedições / etiquetas (ZIP 135 — schema Rui / ZIP 134).
 *
 * Actions:
 *  - preview_payload
 *  - validate → POST registarExpedicao (sem gravar se create flag off… validate ainda chama API)
 *  - create / obtain_label → idempotente; gated por DPD_QA_CREATE_ENABLED
 *  - print_label / get_label → reutiliza guia existente
 *  - tracking
 *
 * Create real OFF por defeito. Nunca business.dpd.pt sem DPD_MODE=live + GO.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  b64ToUint8Array,
  buildExpeditionPayloadCandidate,
  dpdForward,
  dpdOauthTokenForMode,
  DPD_REGISTAR_EXPEDICAO_PATH,
  fetchDpdLabelPdfBytes,
  fetchDpdTrace,
  isDpdPrivateLabelUrl,
  parseRegistarExpedicaoResult,
  type DpdParty,
  type DpdServiceKind,
} from "../_shared/dpd_client.ts";
import {
  assertDpdExecutionAllowed,
  dpdApiBaseForMode,
  dpdCreateEnabledForMode,
  normalizeDpdMode,
} from "../_shared/ops_env.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

type Admin = ReturnType<typeof createClient>;

function partyFromProfile(row: Record<string, unknown> | null): DpdParty | null {
  if (!row) return null;
  const name = String(
    row.legal_full_name ?? row.full_name ?? row.display_name ?? "",
  ).trim();
  const address1 = String(row.shipping_line1 ?? "").trim();
  const zipCode = String(row.shipping_postal_code ?? "").trim();
  const city = String(row.shipping_city ?? "").trim();
  const country = String(row.shipping_country ?? "PT").trim() || "PT";
  if (!name || !address1 || !zipCode || !city) return null;
  return {
    name,
    address1,
    address2: String(row.shipping_line2 ?? "").trim() || undefined,
    zipCode,
    city,
    country,
    phone: String(row.phone ?? row.phone_number ?? "").trim() || undefined,
    email: String(row.email ?? "").trim() || undefined,
  };
}

async function loadOrderContext(admin: Admin, orderId: string) {
  const { data: order, error } = await admin
    .from("orders")
    .select(
      "id,seller_id,buyer_id,status,shipping_method,delivery_point_ref,delivery_point_provider,delivery_point_label,delivery_recipient_name,delivery_line1,delivery_line2,delivery_postal_code,delivery_city,delivery_country,delivery_phone,dpd_expedition_id,dpd_tracking_code,dpd_service,dpd_label_url,dpd_last_error,dpd_created_at,shipping_weight_kg,shipping_free_by_seller,ops_dpd_mode,ops_stripe_mode",
    )
    .eq("id", orderId)
    .maybeSingle();
  if (error || !order) return null;

  // profiles: phone (não phone_number); email vive em auth.users — não seleccionar colunas inexistentes
  const { data: seller } = await admin
    .from("profiles")
    .select(
      "id,full_name,legal_full_name,shipping_line1,shipping_line2,shipping_postal_code,shipping_city,shipping_country,phone",
    )
    .eq("id", order.seller_id)
    .maybeSingle();

  const { data: buyer } = await admin
    .from("profiles")
    .select(
      "id,full_name,legal_full_name,shipping_line1,shipping_line2,shipping_postal_code,shipping_city,shipping_country,phone",
    )
    .eq("id", order.buyer_id)
    .maybeSingle();

  return { order, seller, buyer };
}

function resolveService(order: Record<string, unknown>): DpdServiceKind {
  const stored = String(order.dpd_service ?? "").trim();
  if (stored === "shop_to_shop" || stored === "shop_to_home") return stored;
  const prov = String(order.delivery_point_provider ?? "").trim();
  if (prov === "dpd_pickup") return "shop_to_shop";
  return "shop_to_home";
}

/** Guarda PDF no Storage Fleaber e devolve URL assinada (abre no telemóvel). */
async function persistLabelPdf(
  admin: Admin,
  order: Record<string, unknown>,
  guide: string,
  pdfBytes: Uint8Array,
): Promise<string | null> {
  const orderId = String(order.id ?? "").trim();
  const sellerId = String(order.seller_id ?? "").trim();
  if (!orderId || !sellerId || pdfBytes.length < 100) return null;
  const path = `dpd_labels/${sellerId}/${orderId}/${guide}.pdf`;
  const { error: upErr } = await admin.storage
    .from("fleaber_private")
    .upload(path, pdfBytes, {
      contentType: "application/pdf",
      upsert: true,
    });
  if (upErr) {
    console.error("dpd_label_upload_failed", upErr.message);
    return null;
  }
  const { data: signed, error: signErr } = await admin.storage
    .from("fleaber_private")
    .createSignedUrl(path, 60 * 60 * 24 * 30); // 30 dias
  if (signErr || !signed?.signedUrl) {
    console.error("dpd_label_sign_failed", signErr?.message);
    return null;
  }
  const url = signed.signedUrl;
  await admin.from("orders").update({ dpd_label_url: url }).eq("id", orderId);
  return url;
}

async function ensureFleaberLabelUrl(
  admin: Admin,
  order: Record<string, unknown>,
  opts?: { pdfBase64?: string | null },
): Promise<string | null> {
  const guide = String(
    order.dpd_tracking_code ?? order.dpd_expedition_id ?? "",
  ).trim();
  const current = String(order.dpd_label_url ?? "").trim();
  if (!guide) return current || null;
  if (current && !isDpdPrivateLabelUrl(current)) return current;

  let bytes: Uint8Array | null = null;
  if (opts?.pdfBase64) {
    try {
      bytes = b64ToUint8Array(opts.pdfBase64);
    } catch {
      bytes = null;
    }
  }
  if (!bytes || bytes.length < 100 || bytes[0] !== 0x25) {
    const mode = normalizeDpdMode(order.ops_dpd_mode);
    bytes = await fetchDpdLabelPdfBytes(guide, mode);
  }
  if (!bytes) return current || null;
  return (await persistLabelPdf(admin, order, guide, bytes)) ?? current ?? null;
}

async function existingLabelResponse(
  admin: Admin,
  order: Record<string, unknown>,
) {
  const guide = String(order.dpd_tracking_code ?? "").trim();
  const expId = String(order.dpd_expedition_id ?? "").trim();
  if (!guide && !expId) return null;
  const labelUrl = await ensureFleaberLabelUrl(admin, order);
  return {
    ok: true,
    action: "obtain_label",
    idempotent: true,
    order_id: order.id,
    dpd_tracking_code: guide || null,
    dpd_label_url: labelUrl || null,
    dpd_expedition_id: expId || null,
    user_message: "Etiqueta pronta",
    message:
      "Etiqueta já existente — sem nova expedição DPD (idempotência).",
    order_status_unchanged: true,
    note:
      "Obter etiqueta NÃO marca a encomenda como enviada. Enviado só com aceitação física DPD.",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "auth_required" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  const uid = userData?.user?.id;
  if (!uid) return json({ ok: false, error: "auth_required" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const action = String(body.action ?? "preview_payload").trim();
  const orderId = String(body.order_id ?? "").trim();
  if (!orderId) return json({ ok: false, error: "order_id_required" }, 400);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });
  const ctx = await loadOrderContext(admin, orderId);
  if (!ctx) return json({ ok: false, error: "order_not_found" }, 404);

  const { order, seller, buyer } = ctx;
  if (order.seller_id !== uid && order.buyer_id !== uid) {
    const { data: isAdmin } = await admin.rpc("batata_is_admin");
    if (isAdmin !== true) {
      return json({ ok: false, error: "forbidden" }, 403);
    }
  }

  // Comprador: só tracking / leitura de etiqueta
  const isSeller = order.seller_id === uid;
  if (
    !isSeller &&
    ["create", "obtain_label", "validate", "preview_payload"].includes(action)
  ) {
    const { data: isAdmin } = await admin.rpc("batata_is_admin");
    if (isAdmin !== true) {
      return json({ ok: false, error: "seller_only" }, 403);
    }
  }

  const sender = partyFromProfile(seller as Record<string, unknown>);
  if (
    ["create", "obtain_label", "validate", "preview_payload"].includes(action) &&
    !sender
  ) {
    return json({
      ok: false,
      error: "seller_shipping_incomplete",
      hint:
        "Morada de origem do vendedor obrigatória antes do primeiro envio DPD.",
      user_message: "Completa a morada de envio no perfil antes de obter a etiqueta.",
    }, 422);
  }

  const service = (String(body.service ?? "").trim() as DpdServiceKind) ||
    resolveService(order as Record<string, unknown>);
  const pudoId = String(
    body.pudo_id ?? order.delivery_point_ref ?? "",
  ).trim() || null;

  let recipient: DpdParty;
  if (service === "shop_to_shop" && pudoId) {
    recipient = {
      name: String(
        order.delivery_recipient_name ??
          order.delivery_point_label ??
          pudoId,
      ).trim() || pudoId,
      address1: String(order.delivery_line1 ?? order.delivery_point_label ?? "")
        .trim() || "Pickup DPD",
      zipCode: String(order.delivery_postal_code ?? "").trim() || "0000-000",
      city: String(order.delivery_city ?? "").trim() || "Portugal",
      country: String(order.delivery_country ?? "PT").trim() || "PT",
      phone: String(order.delivery_phone ?? "").trim() || undefined,
    };
  } else {
    const fromSnap = String(order.delivery_line1 ?? "").trim();
    if (fromSnap) {
      recipient = {
        name: String(order.delivery_recipient_name ?? "").trim() ||
          String((buyer as Record<string, unknown>)?.full_name ?? "Comprador"),
        address1: fromSnap,
        address2: String(order.delivery_line2 ?? "").trim() || undefined,
        zipCode: String(order.delivery_postal_code ?? "").trim(),
        city: String(order.delivery_city ?? "").trim(),
        country: String(order.delivery_country ?? "PT").trim() || "PT",
        phone: String(order.delivery_phone ?? "").trim() || undefined,
      };
    } else {
      const b = partyFromProfile(buyer as Record<string, unknown>);
      if (!b) {
        return json({ ok: false, error: "buyer_shipping_incomplete" }, 422);
      }
      recipient = b;
    }
  }

  const weightKg = Number(order.shipping_weight_kg ?? body.weight_kg ?? 1) || 1;
  const built = buildExpeditionPayloadCandidate({
    service,
    sender: sender!,
    recipient,
    pudoId: service === "shop_to_shop" ? pudoId : null,
    orderId,
    weightKg: Math.min(10, Math.max(0.1, weightKg)),
    contactPhone: order.delivery_phone ?? recipient.phone,
    contactEmail: (buyer as Record<string, unknown>)?.email as string | undefined,
  });

  const orderDpdMode = normalizeDpdMode(
    (order as { ops_dpd_mode?: string }).ops_dpd_mode,
  );

  if (action === "preview_payload") {
    return json({
      ok: true,
      action,
      ops_dpd_mode: orderDpdMode,
      create_enabled: dpdCreateEnabledForMode(orderDpdMode),
      service,
      sub_account: built.subAccount,
      endpoint: `${dpdApiBaseForMode(orderDpdMode)}${DPD_REGISTAR_EXPEDICAO_PATH}`,
      payload: built.payload,
      blockers: built.blockers,
      note:
        "ZIP172: endpoint/creds por ops_dpd_mode (não DPD_MODE global). Create gated.",
    });
  }

  if (action === "tracking") {
    const guide = String(
      body.guide ?? order.dpd_tracking_code ?? "",
    ).trim();
    const countrycode = String(body.countrycode ?? "PT").trim();
    const result = await fetchDpdTrace({ guide, countrycode });
    return json({
      ok: result.ok,
      action: "tracking",
      order_id: orderId,
      status: result.status,
      guide: result.guide,
      countrycode: result.countrycode,
      events: result.events,
      message: result.message ?? null,
      http_status: result.http_status ?? null,
    });
  }

  if (action === "print_label" || action === "get_label") {
    const existing = await existingLabelResponse(
      admin,
      order as Record<string, unknown>,
    );
    if (existing) {
      return json(existing);
    }
    return json({
      ok: false,
      error: "label_not_created",
      user_message: "Ainda não há etiqueta DPD para esta encomenda.",
    }, 404);
  }

  if (
    action === "validate" || action === "create" || action === "obtain_label"
  ) {
    // Idempotência: se já há guia, devolver sem novo create
    if (action === "create" || action === "obtain_label") {
      const existing = await existingLabelResponse(
        admin,
        order as Record<string, unknown>,
      );
      if (existing) return json(existing);
    }

    if (built.blockers.length > 0 && action !== "validate") {
      return json({
        ok: false,
        error: "payload_incomplete",
        blockers: built.blockers,
        user_message: "Etiqueta temporariamente indisponível",
      }, 422);
    }

    const needsCreate = action === "create" || action === "obtain_label";
    if (needsCreate) {
      // ZIP 140 — bloquear se diferença portes pendente / peso por confirmar
      const { data: block } = await admin.rpc(
        "batata_order_blocks_dpd_create",
        { p_order_id: orderId },
      );
      if (block && (block as { blocked?: boolean }).blocked === true) {
        return json({
          ok: false,
          error: String((block as { error?: string }).error ?? "blocked"),
          user_message: String(
            (block as { message?: string }).message ??
              "Etiqueta bloqueada até resolver portes/peso.",
          ),
          create_enabled: dpdCreateEnabledForMode(orderDpdMode),
        }, 409);
      }
    }

    // ZIP 172: creds/endpoint por ops_dpd_mode — sem DPD_MODE global.
    const dpdGate = assertDpdExecutionAllowed(orderDpdMode);
    if (!dpdGate.ok) {
      return json({
        ok: false,
        error: dpdGate.error ?? "dpd_env_blocked",
        user_message:
          "Ambiente DPD desta encomenda não permite esta operação.",
        ops_dpd_mode: orderDpdMode,
        create_enabled: false,
      }, 403);
    }
    if (needsCreate && !dpdCreateEnabledForMode(orderDpdMode)) {
      return json({
        ok: false,
        error: "create_disabled",
        user_message:
          "A criação de etiquetas DPD está temporariamente desligada neste ambiente.",
        create_enabled: false,
        ops_dpd_mode: orderDpdMode,
      }, 403);
    }

    try {
      const token = await dpdOauthTokenForMode(orderDpdMode);
      const url = `${dpdApiBaseForMode(orderDpdMode)}${DPD_REGISTAR_EXPEDICAO_PATH}`;
      const fwd = await dpdForward({
        url,
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(built.payload),
      });

      let parsed: unknown = null;
      try {
        parsed = JSON.parse(fwd.bodyText);
      } catch {
        parsed = null;
      }

      const parsedMsg = (parsed as { message?: string } | null)?.message ??
        null;

      if (needsCreate && fwd.ok) {
        const extracted = parseRegistarExpedicaoResult(parsed);
        const patch: Record<string, unknown> = {
          dpd_service: service,
          dpd_last_error: null,
          dpd_created_at: new Date().toISOString(),
          // NÃO alterar status da encomenda para enviado
        };
        if (extracted.expeditionId) {
          patch.dpd_expedition_id = extracted.expeditionId;
        }
        if (extracted.guide) {
          patch.dpd_tracking_code = extracted.guide;
        }
        // Temporário: URL DPD privada — substituída abaixo por Storage Fleaber
        if (extracted.labelUrl) {
          patch.dpd_label_url = extracted.labelUrl;
        } else if (extracted.guide) {
          patch.dpd_label_url =
            `${dpdApiBaseForMode(orderDpdMode)}/api/v1/pt/expedition/etiquetaApi/${extracted.guide}`;
        }
        await admin.from("orders").update(patch).eq("id", orderId);

        const orderAfter = {
          ...(order as Record<string, unknown>),
          ...patch,
        };
        const fleaberUrl = extracted.guide
          ? await ensureFleaberLabelUrl(admin, orderAfter, {
            pdfBase64: extracted.pdfBase64,
          })
          : null;
        if (fleaberUrl) patch.dpd_label_url = fleaberUrl;

        return json({
          ok: true,
          action,
          idempotent: false,
          http_status: fwd.status,
          dpd_message: parsedMsg,
          dpd_tracking_code: extracted.guide,
          dpd_label_url: patch.dpd_label_url ?? null,
          dpd_expedition_id: extracted.expeditionId,
          has_pdf: extracted.hasPdf || Boolean(fleaberUrl),
          user_message: "Etiqueta pronta",
          order_status_unchanged: true,
          note:
            "Etiqueta criada. Encomenda NÃO marcada como enviada até aceitação física DPD.",
        });
      }

      if (needsCreate && !fwd.ok) {
        await admin.from("orders").update({
          dpd_last_error: (parsedMsg || fwd.bodyText).slice(0, 500),
        }).eq("id", orderId);
        return json({
          ok: false,
          action,
          http_status: fwd.status,
          error: "dpd_upstream_error",
          user_message: "Etiqueta temporariamente indisponível",
          dpd_message: parsedMsg,
          response: parsed ?? fwd.bodyText.slice(0, 400),
          retry_safe: true,
        }, 502);
      }

      // validate
      return json({
        ok: fwd.ok,
        action: "validate",
        http_status: fwd.status,
        response: parsed ?? fwd.bodyText.slice(0, 800),
        payload_sent_keys: Object.keys(built.payload),
        blockers: built.blockers,
        endpoint: url,
      });
    } catch (e) {
      if (needsCreate) {
        await admin.from("orders").update({
          dpd_last_error: String(e).slice(0, 500),
        }).eq("id", orderId);
      }
      return json({
        ok: false,
        error: e instanceof Error ? e.message : String(e),
        user_message: "Etiqueta temporariamente indisponível",
        blockers: built.blockers,
        retry_safe: true,
      }, 502);
    }
  }

  return json({ ok: false, error: "unknown_action" }, 400);
});
