/**
 * Ponto 7 — Despacho push (FCM HTTP v1) + e-mail comercial.
 *
 * Secrets (Supabase Edge — nunca no git):
 * - SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto)
 * - FCM_PROJECT_ID
 * - FCM_CLIENT_EMAIL
 * - FCM_PRIVATE_KEY  (PEM; \n escapados)
 * - RESEND_API_KEY (opcional até e-mail activo — NÃO definir sem GO)
 * - MAIL_FROM (ex. Fleaber <notificacoes@fleaber.pt>)
 *
 * Email comercial: E1–E3 + shipping_delta_* / ship_deadline_auto_cancelled (ZIP 142).
 * `seguro_fleaber_paid` = push/inbox only (anti-dup).
 *
 * Body: { notification_id: uuid }
 * Erros → 200 + status skipped/failed (não bloqueia Stripe/checkout).
 * SEM FCM legacy / server key.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { create as createJwt, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import {
  buildCommercialEmail,
  canSendShippedEmail,
  audienceRoleFromDedupe,
  DEFAULT_REFUND_HINT,
  formatCents,
  formatEuro,
  isBundleQuoteEmailKind,
  isShippingDeltaKind,
  orderDeepLinkUrl,
  type OrderEmailContext,
  type OrderLineEmail,
  resolveCommercialOrderId,
  sanitizeImageUrl,
  shortRef,
  wantsCommercialEmail,
  formatDeadlineNaturalPt,
  formatDeadlinePt,
} from "./email_commercial.ts";

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

type NotifRow = {
  id: string;
  user_id: string;
  kind: string;
  title: string;
  body: string;
  chat_id: string | null;
  dedupe_key: string | null;
  actor_id?: string | null;
};

let cachedAccessToken: { token: string; exp: number } | null = null;

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getFcmAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.exp > now + 60) {
    return cachedAccessToken.token;
  }
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL") ?? "";
  const privateKeyPem = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(
    /\\n/g,
    "\n",
  );
  if (!clientEmail || !privateKeyPem) {
    throw new Error("FCM_HTTP_V1_CREDS_MISSING");
  }
  const key = await importPrivateKey(privateKeyPem);
  const assertion = await createJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 55),
    },
    key,
  );
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok || !tokenJson.access_token) {
    throw new Error(
      `oauth_token_fail:${JSON.stringify(tokenJson).slice(0, 200)}`,
    );
  }
  cachedAccessToken = {
    token: String(tokenJson.access_token),
    exp: now + Number(tokenJson.expires_in ?? 3600),
  };
  return cachedAccessToken.token;
}

async function sendFcmHttpV1(
  projectId: string,
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; ref?: string; error?: string }> {
  try {
    const accessToken = await getFcmAccessToken();
    const url =
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title, body },
          data,
          android: { priority: "HIGH" },
        },
      }),
    });
    const text = await res.text();
    if (!res.ok) return { ok: false, error: text.slice(0, 400) };
    try {
      const parsed = JSON.parse(text);
      return { ok: true, ref: String(parsed.name ?? "") };
    } catch {
      return { ok: true, ref: text.slice(0, 80) };
    }
  } catch (e) {
    return { ok: false, error: String(e).slice(0, 300) };
  }
}

async function sendResendEmail(
  apiKey: string,
  from: string,
  to: string,
  subject: string,
  text: string,
  html?: string,
): Promise<{ ok: boolean; ref?: string; error?: string }> {
  const payload: Record<string, unknown> = { from, to, subject, text };
  if (html && html.trim()) payload.html = html;
  const replyTo = Deno.env.get("MAIL_REPLY_TO")?.trim();
  if (replyTo) payload.reply_to = replyTo;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const textBody = await res.text();
  if (!res.ok) return { ok: false, error: textBody.slice(0, 300) };
  try {
    const parsed = JSON.parse(textBody);
    return { ok: true, ref: String(parsed.id ?? "") };
  } catch {
    return { ok: true };
  }
}

function statusLabelPt(status: string): string {
  switch (status) {
    case "pago":
      return "Pago";
    case "enviado":
      return "Enviado";
    case "entregue":
      return "Entregue";
    case "concluido":
      return "Concluído";
    default:
      return status ? status.charAt(0).toUpperCase() + status.slice(1) : "";
  }
}

function firstProductImage(raw: unknown): string | null {
  if (!Array.isArray(raw) || !raw.length) return null;
  return sanitizeImageUrl(String(raw[0] ?? ""));
}

/** Enriquecer contexto: linhas, fotos reais, fees do checkout attempt, DPD. */
async function loadOrderEmailContext(
  admin: ReturnType<typeof createClient>,
  orderId: string | null,
): Promise<OrderEmailContext> {
  const id = (orderId ?? "").trim();
  if (!id) return {};
  const { data: order, error } = await admin
    .from("orders")
    .select(
      "id,price_total,payment_method,product_id,status,shipping_method,bundle_id,quantity,stripe_checkout_session_id,dpd_tracking_code,dpd_expedition_id,dpd_accept_at,buyer_id,seller_id,ship_by_at,stripe_refund_id,stripe_refunded_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (error || !order) {
    return { orderId: id, referenceLabel: shortRef(id), shipmentConfirmed: false };
  }

  const bundleId = String(order.bundle_id ?? "").trim();
  let orderRows: Array<Record<string, unknown>> = [
    order as Record<string, unknown>,
  ];
  if (bundleId) {
    const { data: siblings } = await admin
      .from("orders")
      .select("id,price_total,product_id,quantity,status")
      .eq("bundle_id", bundleId)
      .order("created_at", { ascending: true });
    if (siblings?.length) {
      orderRows = siblings as Array<Record<string, unknown>>;
    }
  }

  const productIds = [
    ...new Set(
      orderRows
        .map((r) => String(r.product_id ?? "").trim())
        .filter(Boolean),
    ),
  ];
  const productMap = new Map<
    string,
    { title: string; imageUrl: string | null; price: number | null }
  >();
  if (productIds.length) {
    const { data: products } = await admin
      .from("products")
      .select("id,title,price,image_urls")
      .in("id", productIds);
    for (const p of products ?? []) {
      const pid = String(p.id ?? "");
      const priceRaw = p.price;
      const priceNum = typeof priceRaw === "number"
        ? priceRaw
        : priceRaw != null
        ? Number(priceRaw)
        : null;
      productMap.set(pid, {
        title: String(p.title ?? "").trim() || "Artigo",
        imageUrl: firstProductImage(p.image_urls),
        price: priceNum != null && !Number.isNaN(priceNum) ? priceNum : null,
      });
    }
  }

  const lines: OrderLineEmail[] = [];
  for (const row of orderRows) {
    const pid = String(row.product_id ?? "").trim();
    const prod = productMap.get(pid);
    const qtyRaw = row.quantity;
    const qty = typeof qtyRaw === "number"
      ? Math.max(1, qtyRaw)
      : Math.max(1, Number(qtyRaw) || 1);
    const linePrice = row.price_total;
    const lineNum = typeof linePrice === "number"
      ? linePrice
      : linePrice != null
      ? Number(linePrice)
      : prod?.price != null
      ? prod.price * qty
      : null;
    lines.push({
      title: prod?.title ?? "Artigo",
      priceLabel: formatEuro(lineNum),
      qty,
      imageUrl: prod?.imageUrl ?? null,
    });
  }

  const pay = String(order.payment_method ?? "").toLowerCase();
  const hasBuyerProtection =
    pay.includes("app") ||
    pay.includes("stripe") ||
    pay.includes("seguro") ||
    pay.includes("protec") ||
    pay.includes("cart");

  let itemsTotalLabel: string | null = null;
  let shippingLabel: string | null = null;
  let protectionLabel: string | null = null;
  let totalLabel: string | null = formatEuro(
    typeof order.price_total === "number"
      ? order.price_total
      : order.price_total != null
      ? Number(order.price_total)
      : null,
  );

  const sessionId = String(order.stripe_checkout_session_id ?? "").trim();
  if (sessionId) {
    const { data: attempt } = await admin
      .from("commerce_checkout_attempts")
      .select("items_cents,shipping_cents,protection_fee_cents,total_cents")
      .eq("stripe_checkout_session_id", sessionId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (attempt) {
      itemsTotalLabel = formatCents(attempt.items_cents as number);
      shippingLabel = formatCents(attempt.shipping_cents as number);
      const prot = Number(attempt.protection_fee_cents ?? 0);
      if (prot > 0) protectionLabel = formatCents(prot);
      totalLabel = formatCents(attempt.total_cents as number) ?? totalLabel;
    }
  }

  // Bundle: somar price_total das linhas se não houver attempt
  if (!sessionId || !itemsTotalLabel) {
    if (orderRows.length > 1) {
      let sum = 0;
      for (const row of orderRows) {
        const p = row.price_total;
        const n = typeof p === "number" ? p : p != null ? Number(p) : 0;
        if (!Number.isNaN(n)) sum += n;
      }
      if (sum > 0) totalLabel = formatEuro(sum);
    }
  }

  const status = String(order.status ?? "").trim().toLowerCase();
  const shipmentConfirmed = status === "enviado" || status === "entregue";
  const guide = String(order.dpd_tracking_code ?? "").trim();
  const acceptAt = order.dpd_accept_at;
  // Etiqueta/guia ≠ «a caminho». Só com aceite real da transportadora.
  const handedToCarrier = !!acceptAt;
  const trackingCode = guide || null;
  const carrierLabel = guide || order.dpd_expedition_id ? "DPD" : null;

  // C1: stripe_refund_id pode existir antes do finalize (só «iniciado»).
  // Concluído = confirmação efectiva na BD: stripe_refunded_at.
  const refundDone = !!order.stripe_refunded_at;
  const refundStarted = refundDone ||
    !!String(order.stripe_refund_id ?? "").trim() ||
    status === "cancelado" ||
    status === "cancelled";

  return {
    orderId: id,
    referenceLabel: shortRef(id),
    productTitle: lines[0]?.title ?? null,
    totalLabel,
    statusLabel: statusLabelPt(status),
    hasBuyerProtection,
    shipmentConfirmed,
    handedToCarrier,
    trackingCode,
    trackingUrl: null,
    carrierLabel,
    itemsTotalLabel,
    shippingLabel,
    protectionLabel,
    lines,
    ctaUrl: orderDeepLinkUrl(id),
    buyerId: String(order.buyer_id ?? "").trim() || null,
    sellerId: String(order.seller_id ?? "").trim() || null,
    shipByAt: order.ship_by_at
      ? String(order.ship_by_at)
      : null,
    refundStatus: refundDone
      ? "completed"
      : refundStarted
      ? "initiated"
      : null,
  };
}

/** Enriquecer contexto com adjustment de portes (ZIP 142) — só leitura C2. */
async function enrichShippingDeltaContext(
  admin: ReturnType<typeof createClient>,
  orderId: string,
  base: OrderEmailContext,
  kind: string,
  recipientUserId: string | null,
  dedupe: string | null,
): Promise<OrderEmailContext> {
  const { data: adj } = await admin
    .from("order_shipping_adjustments")
    .select(
      "id,status,band_from,band_to,shipping_delta_cents,stripe_fee_grossup_cents,amount_charge_cents,expires_at,created_at",
    )
    .eq("order_id", orderId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let audienceRole = audienceRoleFromDedupe(kind, dedupe);
  const uid = (recipientUserId ?? "").trim();
  if (!audienceRole && uid) {
    if (base.buyerId && uid === base.buyerId) audienceRole = "buyer";
    else if (base.sellerId && uid === base.sellerId) audienceRole = "seller";
  }

  return {
    ...base,
    audienceRole,
    adjustmentId: adj ? String(adj.id) : base.adjustmentId,
    weightBandFrom: adj
      ? String(adj.band_from ?? "")
      : base.weightBandFrom,
    weightBandTo: adj ? String(adj.band_to ?? "") : base.weightBandTo,
    shippingDeltaCents: adj != null
      ? Number(adj.shipping_delta_cents)
      : base.shippingDeltaCents,
    stripeFeeGrossupCents: adj != null
      ? Number(adj.stripe_fee_grossup_cents ?? 0)
      : base.stripeFeeGrossupCents,
    amountChargeCents: adj != null
      ? Number(adj.amount_charge_cents)
      : base.amountChargeCents,
    fleaberProtectionCents: 0,
    payDeadlineAt: adj?.expires_at
      ? String(adj.expires_at)
      : base.payDeadlineAt,
    refundHint: base.refundHint ?? DEFAULT_REFUND_HINT,
    deltaCents: adj != null
      ? Number(adj.shipping_delta_cents)
      : base.deltaCents,
  };
}

async function logDelivery(
  admin: ReturnType<typeof createClient>,
  row: {
    notification_id?: string | null;
    user_id?: string | null;
    channel: string;
    kind: string;
    dedupe_key?: string | null;
    status: string;
    provider_ref?: string | null;
    error_text?: string | null;
    meta?: Record<string, unknown>;
  },
) {
  try {
    await admin.from("notification_delivery_log").insert({
      notification_id: row.notification_id ?? null,
      user_id: row.user_id ?? null,
      channel: row.channel,
      kind: row.kind,
      dedupe_key: row.dedupe_key ?? null,
      status: row.status,
      provider_ref: row.provider_ref ?? null,
      error_text: row.error_text ?? null,
      meta: row.meta ?? {},
    });
  } catch (_) {
    /* best-effort */
  }
}

async function alreadySent(
  admin: ReturnType<typeof createClient>,
  dedupe: string | null | undefined,
  channel: string,
): Promise<boolean> {
  if (!dedupe) return false;
  const { data } = await admin
    .from("notification_delivery_log")
    .select("id")
    .eq("dedupe_key", dedupe)
    .eq("channel", channel)
    .eq("status", "sent")
    .limit(1);
  return (data?.length ?? 0) > 0;
}

/** Email comercial: allowlist E1–E3. Push de `seguro_fleaber_paid` mantém-se em wantsPush. */
function wantsEmail(kind: string): boolean {
  return wantsCommercialEmail(kind);
}

function wantsPush(kind: string): boolean {
  const k = kind.toLowerCase();
  return (
    k === "chat_message" ||
    k.startsWith("bundle_") ||
    k.startsWith("price_offer") ||
    k === "seguro_fleaber_paid" ||
    k === "order_paid_buyer" ||
    k === "order_paid_seller" ||
    k === "reservation_order_shipped" ||
    k === "shipping_delta_requested" ||
    k === "shipping_delta_paid" ||
    k === "shipping_delta_expired_cancelled" ||
    k === "ship_deadline_auto_cancelled" ||
    k.startsWith("helper_invitation")
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json({ ok: false, error: "missing_supabase_env" }, 200);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // AuthZ: service_role OU utilizador JWT = actor ou destinatário da notificação.
  const authHeader = req.headers.get("Authorization") ?? "";
  let callerUid: string | null = null;
  let isService = false;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  // ZIP 144.3: chaves novas `sb_secret_…` NÃO são JWT — match exacto ANTES do parse.
  if (token && token === serviceKey) {
    isService = true;
  }
  if (!isService && token) {
    try {
      const payloadPart = token.split(".")[1] ?? "";
      if (payloadPart) {
        const normalized = payloadPart.replace(/-/g, "+").replace(/_/g, "/");
        const pad = normalized.length % 4 === 0
          ? ""
          : "=".repeat(4 - (normalized.length % 4));
        const jsonClaims = JSON.parse(atob(normalized + pad));
        isService = String(jsonClaims.role ?? "") === "service_role";
      }
      if (!isService && anonKey) {
        const userClient = createClient(supabaseUrl, anonKey, {
          global: { headers: { Authorization: authHeader } },
          auth: { persistSession: false },
        });
        const { data: userData } = await userClient.auth.getUser();
        callerUid = userData.user?.id ?? null;
      }
    } catch {
      /* fall through */
    }
  }
  if (!isService && !callerUid) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 200);
  }

  const nid = String(payload.notification_id ?? "").trim();
  const dedupeLookup = String(payload.dedupe_key ?? "").trim();
  if (!nid && !dedupeLookup) {
    return json({ ok: false, error: "notification_id_required" }, 200);
  }

  let data: NotifRow | null = null;
  if (nid) {
    const res = await admin
      .from("user_notifications")
      .select("id,user_id,kind,title,body,chat_id,dedupe_key,actor_id")
      .eq("id", nid)
      .maybeSingle();
    data = (res.data as NotifRow | null) ?? null;
  } else {
    const res = await admin
      .from("user_notifications")
      .select("id,user_id,kind,title,body,chat_id,dedupe_key,actor_id")
      .eq("dedupe_key", dedupeLookup)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    data = (res.data as NotifRow | null) ?? null;
  }
  if (!data) {
    return json({ ok: false, error: "notification_not_found" }, 200);
  }
  const notif = data as NotifRow & { actor_id?: string | null };
  if (
    !isService &&
    callerUid !== notif.user_id &&
    callerUid !== (notif.actor_id ?? "")
  ) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const kind = notif.kind;
  const dedupe = notif.dedupe_key;
  const pushTitle = (notif.title || "Fleaber").slice(0, 80);
  const pushBody = (() => {
    const k = kind.toLowerCase();
    if (k.includes("paid") || k === "seguro_fleaber_paid") {
      return "Actualização da tua compra na Fleaber.";
    }
    if (k.includes("ship")) return "A tua encomenda foi atualizada.";
    if (k === "chat_message") return "Tens uma nova mensagem.";
    return (notif.body || pushTitle).slice(0, 120);
  })();

  const dataPayload: Record<string, string> = {
    kind,
    notification_id: notif.id,
    chat_id: notif.chat_id ?? "",
  };

  const results: Record<string, unknown> = { notification_id: notif.id };
  const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";

  if (wantsPush(kind)) {
    if (await alreadySent(admin, dedupe, "push")) {
      results.push = "skipped_dup";
    } else {
      const { data: tokens } = await admin
        .from("device_push_tokens")
        .select("id,token")
        .eq("user_id", notif.user_id)
        .is("revoked_at", null);

      if (!projectId || !(Deno.env.get("FCM_CLIENT_EMAIL") ?? "")) {
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "push",
          kind,
          dedupe_key: dedupe,
          status: "skipped",
          error_text: "FCM_HTTP_V1_CREDS_MISSING",
        });
        results.push = "skipped_no_fcm";
      } else if (!tokens?.length) {
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "push",
          kind,
          dedupe_key: dedupe,
          status: "skipped",
          error_text: "no_tokens",
        });
        results.push = "skipped_no_tokens";
      } else {
        let anyOk = false;
        for (const row of tokens) {
          const sent = await sendFcmHttpV1(
            projectId,
            row.token,
            pushTitle,
            pushBody,
            dataPayload,
          );
          if (sent.ok) {
            anyOk = true;
            await logDelivery(admin, {
              notification_id: notif.id,
              user_id: notif.user_id,
              channel: "push",
              kind,
              dedupe_key: dedupe,
              status: "sent",
              provider_ref: sent.ref ?? null,
            });
          } else {
            const err = (sent.error ?? "").toLowerCase();
            if (
              err.includes("notfound") ||
              err.includes("unregister") ||
              err.includes("invalid-argument")
            ) {
              await admin
                .from("device_push_tokens")
                .update({ revoked_at: new Date().toISOString() })
                .eq("id", row.id);
            }
            await logDelivery(admin, {
              notification_id: notif.id,
              user_id: notif.user_id,
              channel: "push",
              kind,
              dedupe_key: dedupe,
              status: "failed",
              error_text: sent.error ?? "fcm_v1_fail",
            });
          }
        }
        results.push = anyOk ? "sent" : "failed";
      }
    }
  } else {
    results.push = "n/a";
  }

  if (wantsEmail(kind)) {
    if (await alreadySent(admin, dedupe, "email")) {
      results.email = "skipped_dup";
    } else {
      const apiKey = Deno.env.get("RESEND_API_KEY") ?? "";
      const from = Deno.env.get("MAIL_FROM") ??
        "Fleaber <notificacoes@fleaber.pt>";
      const { data: userData } = await admin.auth.admin.getUserById(
        notif.user_id,
      );
      const to = userData?.user?.email ?? "";

      // ZIP 149 / 152 — emails de conjunto (sem orderId pré-pagamento).
      if (isBundleQuoteEmailKind(kind)) {
        let bundleCtx: OrderEmailContext = {};
        const bundleIdMatch =
          /bundle[_-]?(?:quote_ready|expired|quote_invalidated|proposal|purchase_request)[_:]?([0-9a-f-]{36})/i
            .exec(dedupe) ??
            /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i
              .exec(dedupe);
        const bundleId = bundleIdMatch?.[1] ??
          String((notif as { bundle_id?: string }).bundle_id ?? "").trim();
        if (bundleId) {
          const { data: bRow } = await admin
            .from("product_bundles")
            .select(
              "id, chat_id, product_ids, articles_cents, shipping_cents, protection_cents, grand_total_cents, pay_expires_at, seller_confirm_expires_at, quote_invalidation_reason, buyer_id, seller_id",
            )
            .eq("id", bundleId)
            .maybeSingle();
          if (bRow) {
            const productIds = Array.isArray(bRow.product_ids)
              ? (bRow.product_ids as string[]).map((x) => String(x))
              : [];
            const uniqueIds = [...new Set(productIds.filter(Boolean))];
            let lines: OrderEmailContext["lines"] = [];
            if (uniqueIds.length) {
              const { data: prods } = await admin
                .from("products")
                .select("id, title, price, image_urls")
                .in("id", uniqueIds);
              const byId = new Map(
                (prods ?? []).map((p) => [String(p.id), p]),
              );
              lines = uniqueIds.map((pid) => {
                const p = byId.get(pid);
                const qty = productIds.filter((x) => x === pid).length || 1;
                const imgs = Array.isArray(p?.image_urls)
                  ? (p!.image_urls as string[])
                  : [];
                const img = imgs.map((u) => String(u).trim()).find((u) =>
                  /^https?:\/\//i.test(u)
                ) ?? null;
                const price = p?.price != null
                  ? formatEuro(Number(p.price))
                  : null;
                return {
                  title: String(p?.title ?? "Artigo").trim() || "Artigo",
                  priceLabel: price,
                  qty,
                  imageUrl: img,
                };
              });
            }
            bundleCtx = {
              bundleId,
              chatId: String(bRow.chat_id ?? "").trim() || null,
              articlesTotalLabel: formatCents(bRow.articles_cents),
              shippingLabel: formatCents(bRow.shipping_cents),
              protectionLabel: formatCents(bRow.protection_cents),
              grandTotalLabel: formatCents(bRow.grand_total_cents),
              totalLabel: formatCents(bRow.grand_total_cents),
              payDeadlineLabel: formatDeadlineNaturalPt(bRow.pay_expires_at) ??
                formatDeadlinePt(bRow.pay_expires_at),
              confirmDeadlineLabel:
                formatDeadlineNaturalPt(bRow.seller_confirm_expires_at) ??
                  formatDeadlinePt(bRow.seller_confirm_expires_at),
              expireReason: String(bRow.quote_invalidation_reason ?? "").trim() ||
                null,
              audienceRole: String(bRow.buyer_id ?? "") === notif.user_id
                ? "buyer"
                : "seller",
              lines,
            };
          }
        }
        const built = buildCommercialEmail(kind, bundleCtx);
        if (!built) {
          results.email = "failed_build";
        } else if (!apiKey || !to) {
          await logDelivery(admin, {
            notification_id: notif.id,
            user_id: notif.user_id,
            channel: "email",
            kind,
            dedupe_key: dedupe,
            status: "skipped",
            error_text: !apiKey ? "RESEND_API_KEY missing" : "no_email",
            meta: {
              subject: built.subject,
              cta: built.ctaUrl,
              dry_run_ready: true,
              bundle: true,
            },
          });
          results.email = "skipped";
          results.email_subject = built.subject;
          results.email_ready = true;
        } else {
          const sent = await sendResendEmail(
            apiKey,
            from,
            to,
            built.subject,
            built.text,
            built.html,
          );
          await logDelivery(admin, {
            notification_id: notif.id,
            user_id: notif.user_id,
            channel: "email",
            kind,
            dedupe_key: dedupe,
            status: sent.ok ? "sent" : "failed",
            provider_ref: sent.ref ?? null,
            error_text: sent.error ?? null,
            meta: { subject: built.subject, cta: built.ctaUrl, bundle: true },
          });
          results.email = sent.ok ? "sent" : "failed";
        }
      } else {
      const orderId = resolveCommercialOrderId({ dedupe });
      if (!orderId) {
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "email",
          kind,
          dedupe_key: dedupe,
          status: "failed",
          error_text: "missing_order_id",
          meta: {
            reason:
              "Commercial email requires real orders.id in dedupe (order_paid:uuid:role | shipped:uuid)",
            dedupe,
            retryable: true,
          },
        });
        results.email = "failed_missing_order_id";
      } else {
      let orderCtx = await loadOrderEmailContext(admin, orderId);
      if (isShippingDeltaKind(kind)) {
        orderCtx = await enrichShippingDeltaContext(
          admin,
          orderId,
          orderCtx,
          kind,
          notif.user_id,
          dedupe,
        );
      }
      // E3: só com status=enviado (etiqueta/create DPD sozinha não dispara email).
      if (
        kind.trim().toLowerCase() === "reservation_order_shipped" &&
        !canSendShippedEmail(orderCtx)
      ) {
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "email",
          kind,
          dedupe_key: dedupe,
          status: "skipped",
          error_text: "shipment_not_confirmed",
          meta: {
            reason: "orders.status must be enviado before E3 email",
            order_id: orderId,
          },
        });
        results.email = "skipped_not_shipped";
      } else {
      const built = buildCommercialEmail(kind, orderCtx);
      if (!built) {
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "email",
          kind,
          dedupe_key: dedupe,
          status: "failed",
          error_text: "commercial_build_rejected",
          meta: {
            reason: "buildCommercialEmail null (missing order deep link)",
            order_id: orderId,
            retryable: true,
          },
        });
        results.email = "failed_build";
      } else if (!apiKey || !to) {
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "email",
          kind,
          dedupe_key: dedupe,
          status: "skipped",
          error_text: !apiKey ? "RESEND_API_KEY missing" : "no_email",
          meta: {
            subject: built.subject,
            cta: built.ctaUrl,
            dry_run_ready: true,
          },
        });
        results.email = "skipped";
        results.email_subject = built.subject;
        results.email_ready = true;
      } else {
        const sent = await sendResendEmail(
          apiKey,
          from,
          to,
          built.subject,
          built.text,
          built.html,
        );
        await logDelivery(admin, {
          notification_id: notif.id,
          user_id: notif.user_id,
          channel: "email",
          kind,
          dedupe_key: dedupe,
          status: sent.ok ? "sent" : "failed",
          provider_ref: sent.ref ?? null,
          error_text: sent.error ?? null,
          meta: { subject: built.subject, cta: built.ctaUrl },
        });
        results.email = sent.ok ? "sent" : "failed";
      }
      } // end E3 gate else
      } // end orderId resolved
      } // end non-bundle email
    }
  } else {
    results.email = "n/a";
  }

  return json({ ok: true, ...results });
});
