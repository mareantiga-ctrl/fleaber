/**
 * ZIP 184 — one-shot QA samples for Rui Ribeiro (DPD).
 * Creates Shop→Shop + Shop→Home on qabusiness.dpd.pt only.
 * Auth: x-ops-health-secret == OPS_HEALTH_SECRET (or Bearer service_role).
 * Never touches business.dpd.pt / LIVE.
 */
import {
  buildExpeditionPayloadCandidate,
  dpdForward,
  dpdOauthTokenForMode,
  DPD_REGISTAR_EXPEDICAO_PATH,
  fetchDpdLabelPdfBytes,
  parseRegistarExpedicaoResult,
  type DpdParty,
} from "../_shared/dpd_client.ts";
import { dpdApiBaseForMode } from "../_shared/ops_env.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-ops-health-secret",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

function authorized(req: Request): boolean {
  const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const auth = (req.headers.get("Authorization") ?? "").trim();
  if (serviceRole && auth === `Bearer ${serviceRole}`) return true;
  const secret = (Deno.env.get("OPS_HEALTH_SECRET") ?? "").trim();
  const header = (req.headers.get("x-ops-health-secret") ?? "").trim();
  return secret.length > 0 && header === secret;
}

async function createOne(opts: {
  service: "shop_to_shop" | "shop_to_home";
  pudoId: string | null;
  ref: string;
  sender: DpdParty;
  recipient: DpdParty;
}): Promise<Record<string, unknown>> {
  const built = buildExpeditionPayloadCandidate({
    service: opts.service,
    sender: opts.sender,
    recipient: opts.recipient,
    pudoId: opts.pudoId,
    orderId: opts.ref,
    weightKg: 1,
  });
  if (built.blockers.length) {
    return {
      ok: false,
      service: opts.service,
      blockers: built.blockers,
    };
  }

  const token = await dpdOauthTokenForMode("qa");
  const base = dpdApiBaseForMode("qa");
  if (!base.includes("qabusiness.dpd.pt")) {
    return {
      ok: false,
      error: "refused_non_qa_base",
      base,
    };
  }

  const requestSanitized = {
    endpoint: `${base}${DPD_REGISTAR_EXPEDICAO_PATH}`,
    sub_account: built.payload.sub_account,
    destinatario_usar_endereco_pickup:
      built.payload.destinatario_usar_endereco_pickup,
    recipient_pickup_store: built.payload.recipient_pickup_store,
    shipper: built.payload.shipper,
    address: built.payload.address,
    encomenda_referencia: built.payload.encomenda_referencia,
    expedition_date: built.payload.expedition_date,
    encomenda_peso_envio: built.payload.encomenda_peso_envio,
  };

  const fwd = await dpdForward({
    url: `${base}${DPD_REGISTAR_EXPEDICAO_PATH}`,
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
    parsed = { raw_preview: fwd.bodyText.slice(0, 400) };
  }
  const msg = (parsed as { message?: string } | null)?.message ?? null;
  const parsedGuide = parseRegistarExpedicaoResult(parsed);
  let pdfB64: string | null = parsedGuide.pdfBase64;
  let pdfLen = pdfB64 ? Math.floor((pdfB64.length * 3) / 4) : 0;

  if ((!pdfB64 || pdfLen < 100) && parsedGuide.guide) {
    const bytes = await fetchDpdLabelPdfBytes(parsedGuide.guide, "qa");
    if (bytes && bytes.length > 100) {
      let bin = "";
      for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
      pdfB64 = btoa(bin);
      pdfLen = bytes.length;
    }
  }

  return {
    ok: fwd.ok && !!parsedGuide.guide,
    service: opts.service,
    sub_account: built.subAccount,
    http_status: fwd.status,
    message: msg,
    num_guia: parsedGuide.guide,
    pdf_url: parsedGuide.labelUrl,
    pdf_len: pdfLen,
    pdf_base64: pdfB64 && pdfLen > 100 ? pdfB64 : null,
    request_sanitized: requestSanitized,
    response_sanitized: {
      status_code: (parsed as { status_code?: number } | null)?.status_code ??
        fwd.status,
      message: msg,
      result: {
        num_guia: parsedGuide.guide ? [parsedGuide.guide] : [],
        pdf_url: parsedGuide.labelUrl,
        pdf: parsedGuide.hasPdf || (pdfLen > 100)
          ? `<redacted len=${pdfLen}>`
          : null,
      },
    },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }
  if (!authorized(req)) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const action = String(body.action ?? "create").trim();
  if (action === "fetch_label") {
    const guide = String(body.guide ?? "").trim();
    if (!guide) return json({ ok: false, error: "guide_required" }, 400);
    const bytes = await fetchDpdLabelPdfBytes(guide, "qa");
    if (!bytes || bytes.length < 100) {
      return json({ ok: false, error: "label_fetch_failed", guide }, 502);
    }
    let bin = "";
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return json({
      ok: true,
      action: "fetch_label",
      guide,
      pdf_len: bytes.length,
      pdf_base64: btoa(bin),
    });
  }

  // Hard stop if create flag off
  const createOn = (Deno.env.get("DPD_QA_CREATE_ENABLED") ?? "").trim() === "1";
  if (!createOn) {
    return json({
      ok: false,
      error: "dpd_qa_create_disabled",
      hint: "Set DPD_QA_CREATE_ENABLED=1 only for this QA sample run.",
    }, 403);
  }

  const only = String(body.only ?? "both").trim(); // both | shop_to_shop | shop_to_home
  const includePdf = body.include_pdf !== false;

  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, "").slice(0, 14);
  const sender: DpdParty = {
    name: "QA Fleaber Seller",
    address1: "Rua Teste Remetente 1",
    zipCode: "1000-100",
    city: "Lisboa",
    country: "PT",
    phone: "912345678",
    email: "qa-seller@fleaber.app",
  };
  const recipientHome: DpdParty = {
    name: "QA Fleaber Buyer",
    address1: "Rua de Santa Catarina 100",
    zipCode: "4000-070",
    city: "Porto",
    country: "PT",
    phone: "913456789",
    email: "qa-buyer@fleaber.app",
  };
  const recipientShop: DpdParty = {
    name: "QA Fleaber Buyer",
    address1: "Pickup DPD",
    zipCode: "4700-000",
    city: "Braga",
    country: "PT",
    phone: "913456789",
    email: "qa-buyer@fleaber.app",
  };

  let s2s: Record<string, unknown> | null = null;
  let s2h: Record<string, unknown> | null = null;

  if (only === "both" || only === "shop_to_shop") {
    try {
      s2s = await createOne({
        service: "shop_to_shop",
        pudoId: "PT11479",
        ref: `QA184S2S${stamp}`.slice(0, 16),
        sender,
        recipient: recipientShop,
      });
    } catch (e) {
      s2s = {
        ok: false,
        service: "shop_to_shop",
        error: String((e as Error)?.message ?? e),
      };
    }
  }
  if (only === "both" || only === "shop_to_home") {
    try {
      s2h = await createOne({
        service: "shop_to_home",
        pudoId: null,
        ref: `QA184S2H${stamp}`.slice(0, 16),
        sender,
        recipient: recipientHome,
      });
    } catch (e) {
      s2h = {
        ok: false,
        service: "shop_to_home",
        error: String((e as Error)?.message ?? e),
      };
    }
  }

  // Strip pdf_base64 unless requested (keeps response small)
  const strip = (row: Record<string, unknown> | null) => {
    if (!row) return null;
    if (includePdf) return row;
    const copy = { ...row };
    delete copy.pdf_base64;
    return copy;
  };

  const s2sOut = strip(s2s);
  const s2hOut = strip(s2h);
  const okS2s = only === "shop_to_home" ? true : s2sOut?.ok === true;
  const okS2h = only === "shop_to_shop" ? true : s2hOut?.ok === true;

  return json({
    ok: okS2s && okS2h,
    zip: "184",
    mode: "QA_only",
    base: "https://qabusiness.dpd.pt",
    created_at_utc: new Date().toISOString(),
    only,
    shop_to_shop: s2sOut,
    shop_to_home: s2hOut,
    note:
      "Dados fictícios QA. Sem PROD/LIVE. Pickup S2S = PT11479 (GUIZMO SHOP Braga).",
  });
});
