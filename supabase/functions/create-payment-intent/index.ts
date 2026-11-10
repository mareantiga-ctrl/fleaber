import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { sanitizeWebReturnOrigin } from "../_shared/web_return.ts";
import { assertDestructiveHarnessAllowed } from "../_shared/destructive_harness_gate.ts";
import {
  assertStripeLivePilotCheckout,
  isStripeLiveGlobalGo,
  normalizeStripeMode,
  resolveStripeSecretForMode,
} from "../_shared/ops_env.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type BagCheckoutLine = {
  order_id?: string;
  product_id?: string;
  seller_id?: string;
  quantity?: number;
  line_total_cents?: number;
  live_item_id?: string;
  reservation_request_id?: string;
  item_label?: string;
};

type PaymentIntentRequest = {
  amount?: number;
  currency?: string;
  product_id?: string;
  buyer_id?: string;
  seller_id?: string;
  order_id?: string;
  quantity?: number;
  item_price?: number;
  shipping?: number;
  protection_fee?: number;
  shipping_method?: string;
  live_id?: string;
  playback_id?: string;
  is_live?: boolean;
  live_seller_id?: string;
  live_item_id?: string;
  reservation_request_id?: string;
  prize_shipping?: boolean;
  bag_checkout?: boolean;
  bag_lines?: BagCheckoutLine[];
  /** Phase 4 canonical attempt id (shared across bag order lines). */
  checkout_attempt_id?: string;
  /** Chrome Hub: origin para redirect pós-pagamento (ex. https://fleaber.pt). */
  web_return_origin?: string;
};

/** Portes transportadora — alinhado a `kFleaberCarrierShippingEur` / fee_calculator. */
/** Legado 3,50 € — só se DPD_SHIPPING_RATES_LIVE≠1. */
const LEGACY_CARRIER_SHIPPING_CENTS = 350;

/** Tabela Célia (IVA incl.) — espelho de dpd_shipping_rates / Flutter. */
const DPD_RATE_CENTS: Record<string, Record<string, number>> = {
  shop_to_shop: { "0_3": 299, "3_6": 349, "6_10": 499 },
  shop_to_home: { "0_3": 449, "3_6": 599, "6_10": 899 },
};

function dpdRatesLive(): boolean {
  return (Deno.env.get("DPD_SHIPPING_RATES_LIVE") ?? "").trim() === "1";
}
function dpdHomeChargesEnabled(): boolean {
  return (Deno.env.get("DPD_HOME_CHARGES_ENABLED") ?? "").trim() === "1";
}

function dpdBandFromKg(kg: number): string | null {
  if (!(kg > 0)) return null;
  if (kg <= 3) return "0_3";
  if (kg <= 6) return "3_6";
  if (kg <= 10) return "6_10";
  return null;
}

/** Portes DPD Célia a partir de modalidade + peso (default 0–3 kg). */
function dpdShippingCents(opts: {
  modality: "shop_to_shop" | "shop_to_home";
  weightKg?: number | null;
  band?: string | null;
  freeBySeller?: boolean;
}): number {
  if (opts.freeBySeller) return 0;
  if (!dpdRatesLive()) return LEGACY_CARRIER_SHIPPING_CENTS;
  if (opts.modality === "shop_to_home" && !dpdHomeChargesEnabled()) {
    throw new Error(
      "Entrega ao domicílio DPD ainda não activada (combustível).",
    );
  }
  let band = (opts.band ?? "").trim();
  if (!band || !["0_3", "3_6", "6_10"].includes(band)) {
    const kg = Number(opts.weightKg ?? 0);
    if (!(kg > 0)) {
      throw new Error(
        "Portes DPD: peso ou escalão obrigatório (não se assume 0–3 kg).",
      );
    }
    band = dpdBandFromKg(kg) ?? "";
  }
  if (!band || !["0_3", "3_6", "6_10"].includes(band)) {
    throw new Error("Portes DPD: escalão inválido ou acima de 10 kg.");
  }
  const cents = DPD_RATE_CENTS[opts.modality]?.[band];
  if (cents == null) throw new Error("Portes DPD: escalão em falta.");
  return cents;
}
const PROTECTION_FIXED_EUR = 0.65;
const PROTECTION_PCT = 0.05;

async function unitPriceEurForCheckout(
  admin: ReturnType<typeof createClient>,
  liveItemId?: string,
  productId?: string,
): Promise<number> {
  let unit = 0;
  const liid = liveItemId?.trim() ?? "";
  const pid = productId?.trim() ?? "";
  if (liid.length > 0) {
    const { data, error } = await admin
      .from("live_items")
      .select("price")
      .eq("id", liid)
      .maybeSingle();
    if (!error && data?.price != null) {
      unit = Number(data.price);
    }
  }
  if (unit <= 0 && pid.length > 0) {
    const { data, error } = await admin
      .from("products")
      .select("price")
      .eq("id", pid)
      .maybeSingle();
    if (!error && data?.price != null) {
      unit = Number(data.price);
    }
  }
  return unit;
}

function euroToCents(eur: number): number {
  return Math.round(eur * 100);
}

function protectionFeeCents(itemsCents: number, shippingCents: number): number {
  const baseEur = (itemsCents + shippingCents) / 100;
  if (!(baseEur > 0)) return 0;
  const feeEur =
    Math.round((PROTECTION_FIXED_EUR + baseEur * PROTECTION_PCT) * 100) / 100;
  return euroToCents(feeEur);
}

/** Alinhado a batata_is_off_platform_payment (fold + non-ASCII fail-closed). */
function normalizePaymentMethodKey(method?: string | null): string {
  let m = (method ?? "").normalize("NFKC");
  m = m.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  m = m.normalize("NFC").toLowerCase().trim();
  m = m.replace(
    /[\u200b\u200c\u200d\ufeff\u00ad\u2800-\u28ff\u2060\u3164\u202a-\u202e\ue000-\uf8ff]/g,
    "",
  );
  m = m.replace(/[\u00a0\u2028\u2029]/g, " ");
  const map: Record<string, string> = {
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "і": "i", "ї": "i", "м": "m", "ԝ": "w", "μ": "m", "µ": "m",
    "ω": "w", "β": "b", "ɓ": "b", "ɑ": "a", "ѕ": "s", "ⲙ": "m",
    "ᴀ": "a", "ʙ": "b", "ᴄ": "c", "ᴅ": "d", "ᴇ": "e", "ғ": "f", "ɢ": "g",
    "ʜ": "h", "ɪ": "i", "ᴊ": "j", "ᴋ": "k", "ʟ": "l", "ᴍ": "m", "ɴ": "n",
    "ᴏ": "o", "ᴘ": "p", "ǫ": "q", "ʀ": "r", "s": "s", "ᴛ": "t", "ᴜ": "u",
    "ᴠ": "v", "ᴡ": "w", "x": "x", "ʏ": "y", "ᴢ": "z", "㎆": "mb",
  };
  m = m.split("").map((ch) => map[ch] ?? ch).join("");
  // Drop remaining non-ascii (math bold, etc.)
  m = m.replace(/[^\x20-\x7e]/g, "");
  m = m.replace(/\s+/g, " ").trim();
  return m;
}

function paymentMethodCompact(method?: string | null): string {
  return normalizePaymentMethodKey(method).replace(/[^a-z0-9]/g, "");
}

function isOffPlatformPaymentMethod(method?: string | null): boolean {
  const raw = method ?? "";
  const m = normalizePaymentMethodKey(method);
  const compact = paymentMethodCompact(m);
  // Plataforma — nunca off por substring (Pagamento na App)
  const platformCompact = new Set([
    "card",
    "stripe",
    "applepay",
    "googlepay",
    "paypal",
    "pagamentonaapp",
    "naapp",
    "inapp",
    "fleaber",
  ]);
  if (platformCompact.has(compact)) return false;
  const offCompact = new Set([
    "mbway",
    "transferencia",
    "transfer",
    "transf",
    "pagamentodirecto",
    "pagamentodireto",
    "directo",
    "direto",
    "entregaemmao",
    "emmao",
    "levantamento",
    "combinado",
    "combinada",
    "pagamentodiretoaovendedormbwaytransf",
    "pagamentodirectoaovendedormbwaytransf",
    "multibanco",
    "ifthenpay",
    "sibs",
    "contrareembolso",
    "cashondelivery",
    "cod",
    "pagamentoacobranca",
    "referenciamultibanco",
    "bizum",
  ]);
  if (offCompact.has(compact)) return true;
  const off = new Set([
    "mb way",
    "mb_way",
    "mb-way",
    "mbway",
    "transferencia",
    "transferência",
    "transfer",
    "transf",
    "pagamento directo",
    "pagamento direto",
    "pagamento_directo",
    "pagamento_direto",
    "directo",
    "direto",
    "entrega em mao",
    "entrega em mão",
    "em mao",
    "em mão",
    "levantamento",
    "combinado",
    "combinada",
    "pagamento direto ao vendedor (mb way/transf)",
    "pagamento directo ao vendedor (mb way/transf)",
    "multibanco",
    "multi banco",
    "referencia multibanco",
    "ifthenpay",
    "if then pay",
    "sibs",
    "contra reembolso",
    "contra-reembolso",
    "contrareembolso",
    "cash on delivery",
    "cod",
    "pagamento a cobranca",
    "pagamento à cobrança",
    "bizum",
  ]);
  if (m && off.has(m)) return true;
  // DH P1-2: wrap ASCII (mb way x, xxmbway, via mb way, transferencia extra)
  if (compact.includes("mbway")) return true;
  if (compact.includes("transferencia") || compact.includes("transfer")) {
    return true;
  }
  // DZ P2: Multibanco / Ifthenpay / COD / SIBS
  if (compact.includes("multibanco")) return true;
  if (compact.includes("ifthenpay") || compact.includes("ifthen")) return true;
  if (
    compact.includes("contrareembolso") ||
    compact.includes("cashondelivery")
  ) {
    return true;
  }
  if (compact.includes("sibs")) return true;
  if (compact.includes("bizum")) return true;
  // Non-ASCII residual no raw → fail-closed off (não abrir Stripe)
  if (/[^\u0000-\u007f]/.test(raw) && compact.length > 0) {
    return true;
  }
  return false;
}

/**
 * Portes: allowlist EXACTA de códigos/labels suportados (Flutter + códigos).
 * Sem regex/substring — garbage / €0 / misturas → throw.
 */
function shippingCentsFromMethod(method?: string): number {
  const m = (method ?? "").trim().toLowerCase();
  if (!m) throw new Error("Portes inválidos.");

  const handExact = new Set([
    "hand",
    "mao",
    "mão",
    "pickup",
    "entrega_mao",
    "entrega_mão",
    "entrega em mao",
    "entrega em mão",
    "levantamento",
    "entrega em mão (€0.00)",
    "entrega em mao (€0.00)",
  ]);
  const carrierExact = new Set([
    "carrier",
    "transportadora",
    "dpd",
    "envio dpd",
    "envio dpd (3,50 €)",
    "envio dpd (€3.50)",
    "envio dpd (€3,50)",
    // legado — não expor CTT na UI
    "ctt",
    "correios",
    "envio transportadora (€3.50)",
    "envio transportadora (€3,50)",
    "envio transportadora (3,50 €)",
  ]);
  if (handExact.has(m)) return 0;
  if (carrierExact.has(m)) {
    // Sem peso/escalão selado → falha (resolveOrderShippingCents / body).
    throw new Error(
      "Portes DPD: peso ou escalão obrigatório na encomenda.",
    );
  }

  throw new Error("Portes inválidos.");
}

type OrderShipCtx = {
  shipping_method?: string | null;
  delivery_point_ref?: string | null;
  dpd_service?: string | null;
  shipping_weight_kg?: number | null;
  shipping_weight_band?: string | null;
  shipping_weight_charged_kg?: number | null;
  shipping_weight_charged_band?: string | null;
  shipping_modality?: string | null;
  shipping_cents_charged?: number | null;
  shipping_free_by_seller?: boolean | null;
};

/** Portes a partir do selo da encomenda (Pickup → S2S, Home → S2H). */
function resolveOrderShippingCents(
  order: OrderShipCtx,
  bodyMethod?: string,
  bodyExtras?: {
    shipping_weight_kg?: number | null;
    shipping_weight_band?: string | null;
    shipping_modality?: string | null;
  },
): number {
  // ZIP 144.3: selo cobrado (begin/CPI) é a fonte de verdade — não recalcular no settle.
  const sealedCents = Number(order.shipping_cents_charged);
  if (Number.isFinite(sealedCents) && sealedCents >= 0) {
    return Math.trunc(sealedCents);
  }

  const sealedShip = String(order.shipping_method ?? "").trim();
  const method = sealedShip.length > 0
    ? sealedShip
    : String(bodyMethod ?? "").trim();
  if (!method) throw new Error("Portes inválidos.");
  const m = method.toLowerCase();
  const handExact = new Set([
    "hand",
    "mao",
    "mão",
    "pickup",
    "entrega_mao",
    "entrega_mão",
    "entrega em mao",
    "entrega em mão",
    "levantamento",
    "entrega em mão (€0.00)",
    "entrega em mao (€0.00)",
  ]);
  if (handExact.has(m) || m.includes("mão") || m.includes("mao")) {
    // "pickup" no allowlist antigo = mão; Pickup DPD usa delivery_point_ref.
    if (!(m === "pickup" && String(order.delivery_point_ref ?? "").trim())) {
      return 0;
    }
  }

  const svc = String(
    order.dpd_service ?? bodyExtras?.shipping_modality ?? "",
  ).trim().toLowerCase();
  const hasPickup = String(order.delivery_point_ref ?? "").trim().length > 0;
  const modality: "shop_to_shop" | "shop_to_home" =
    hasPickup || svc === "shop_to_shop"
      ? "shop_to_shop"
      : svc === "shop_to_home"
      ? "shop_to_home"
      : "shop_to_shop";

  const band = order.shipping_weight_charged_band ??
    order.shipping_weight_band ??
    bodyExtras?.shipping_weight_band ??
    null;
  const kg = order.shipping_weight_charged_kg ??
    order.shipping_weight_kg ??
    bodyExtras?.shipping_weight_kg ??
    null;

  return dpdShippingCents({
    modality,
    weightKg: kg,
    band,
    freeBySeller: order.shipping_free_by_seller === true,
  });
}

/** ZIP 140 — persistir selo de portes cobrados (reconciliação). */
async function sealOrderShippingCharged(
  admin: ReturnType<typeof createClient>,
  orderId: string,
  opts: {
    shippingCents: number;
    weightKg?: number | null;
    band?: string | null;
    modality?: string | null;
  },
): Promise<void> {
  const id = (orderId ?? "").trim();
  if (!id) return;
  const patch: Record<string, unknown> = {
    shipping_cents_charged: opts.shippingCents,
  };
  const band = (opts.band ?? "").trim();
  if (band) {
    patch.shipping_weight_band = band;
    patch.shipping_weight_charged_band = band;
  }
  const kg = Number(opts.weightKg ?? 0);
  if (kg > 0) {
    patch.shipping_weight_kg = kg;
    patch.shipping_weight_charged_kg = kg;
  }
  const mod = (opts.modality ?? "").trim();
  if (mod === "shop_to_shop" || mod === "shop_to_home" || mod === "hand") {
    patch.shipping_modality = mod;
    if (mod !== "hand") patch.dpd_service = mod;
  }
  await admin.from("orders").update(patch).eq("id", id);
}

function clampQty(raw: unknown): number {
  const n = Number(raw ?? 1);
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.min(Math.floor(n), 99);
}

type OrderCheckoutRow = {
  id: string;
  buyer_id: string | null;
  seller_id: string | null;
  product_id: string | null;
  live_item_id: string | null;
  live_id: string | null;
  live_raffle_id: string | null;
  quantity: number | null;
  status: string | null;
  payment_method: string | null;
  shipping_method: string | null;
  stripe_payment_intent_id?: string | null;
  stripe_checkout_session_id?: string | null;
  stripe_refund_id?: string | null;
  amount_paid_cents?: number | null;
  /** P1-01: unitário selado na criação (cêntimos). */
  contract_unit_cents?: number | null;
  contract_qty?: number | null;
  bundle_id?: string | null;
  product_offer_id?: string | null;
  delivery_point_ref?: string | null;
  dpd_service?: string | null;
  shipping_weight_kg?: number | null;
  shipping_weight_band?: string | null;
  shipping_weight_charged_kg?: number | null;
  shipping_weight_charged_band?: string | null;
  shipping_modality?: string | null;
  shipping_cents_charged?: number | null;
  shipping_free_by_seller?: boolean | null;
  checkout_attempt_id?: string | null;
};

type ServerCheckoutQuote = {
  amountCents: number;
  itemsCents: number;
  shippingCents: number;
  protectionCents: number;
  isPrizeShipping: boolean;
  /** IDs autoritativos derivados das orders (nunca do body). */
  authProductId: string;
  authSellerId: string;
  authBuyerId: string;
  authOrderId: string;
  authLiveItemId: string;
  authLiveId: string;
  lineQuotes: Array<{
    order_id?: string;
    product_id?: string;
    live_item_id?: string;
    quantity: number;
    unit_eur: number;
    line_items_cents: number;
  }>;
};

/**
 * P0-01 raffle authority: status/payment_method NÃO bastam.
 * Prémio financeiro só se:
 *  - order.live_raffle_id ligado a rifa real
 *  - buyer é vencedor em live_raffle_winners
 *  - product/live_item coerentes com a rifa
 *  - status ainda premio_rifa (checkout de portes)
 */
async function isAuthoritativePrizeOrder(
  admin: ReturnType<typeof createClient>,
  order: OrderCheckoutRow,
  buyerId: string,
): Promise<boolean> {
  const st = String(order.status ?? "").toLowerCase().trim();
  if (st !== "premio_rifa") return false;

  const raffleId = String(order.live_raffle_id ?? "").trim();
  if (!raffleId) return false;

  const { data: winner, error: winnerErr } = await admin
    .from("live_raffle_winners")
    .select("id")
    .eq("raffle_id", raffleId)
    .eq("user_id", buyerId)
    .maybeSingle();
  if (winnerErr || !winner) return false;

  const { data: raffle, error: raffleErr } = await admin
    .from("live_raffles")
    .select("id, live_item_id, live_id")
    .eq("id", raffleId)
    .maybeSingle();
  if (raffleErr || !raffle) return false;

  const raffleLi = String(raffle.live_item_id ?? "").trim();
  const orderLi = String(order.live_item_id ?? "").trim();
  if (raffleLi.length > 0) {
    if (orderLi.length > 0 && orderLi !== raffleLi) return false;
    const { data: li, error: liErr } = await admin
      .from("live_items")
      .select("product_id, checkout_product_id")
      .eq("id", raffleLi)
      .maybeSingle();
    if (liErr || !li) return false;
    const prizeProduct = String(
      (li.product_id as string | null) ??
        (li.checkout_product_id as string | null) ??
        "",
    ).trim();
    const orderProduct = String(order.product_id ?? "").trim();
    if (
      prizeProduct.length > 0 &&
      orderProduct.length > 0 &&
      prizeProduct !== orderProduct
    ) {
      return false;
    }
  }

  return true;
}

/**
 * RTI4-1916: bypass montra (unlist) com directo ACTIVO.
 * live_raffle_id no JWT NÃO conta (prémio via RPC; strip deixava hold fantasma).
 *
 * + BATATA Hub bag: produtos sombra `checkout_product_id` (list_on_marketplace=false)
 * devem continuar pagáveis após o directo terminar (janela «X dias para pagar»).
 * Sem isto o Pagar no Hub fica a girar / 400 «product is not listed».
 */
async function orderHasActiveLiveUnlistBypass(
  admin: ReturnType<typeof createClient>,
  order: OrderCheckoutRow,
): Promise<boolean> {
  const liveItemId = String(order.live_item_id ?? "").trim();
  const liveId = String(order.live_id ?? "").trim();
  const productId = String(order.product_id ?? "").trim();
  const sellerId = String(order.seller_id ?? "").trim();

  const liveIsActive = (row: {
    is_active?: boolean | null;
    status?: string | null;
  } | null): boolean => {
    if (!row) return false;
    if (row.is_active === true) return true;
    const st = String(row.status ?? "").toLowerCase().trim();
    return st === "live" || st === "ao_vivo" || st === "active";
  };

  if (liveItemId) {
    const { data: li } = await admin
      .from("live_items")
      .select("live_id, seller_id, product_id, checkout_product_id")
      .eq("id", liveItemId)
      .maybeSingle();
    if (li) {
      const itemLive = String(li.live_id ?? "").trim();
      if (itemLive && (!liveId || liveId === itemLive)) {
        const liProd = String(li.product_id ?? "").trim();
        const liCheckout = String(li.checkout_product_id ?? "").trim();
        const productOk =
          !productId ||
          productId === liProd ||
          productId === liCheckout;
        const itemSeller = String(li.seller_id ?? "").trim();
        const sellerOk =
          !sellerId || !itemSeller || sellerId === itemSeller;

        // Sombra live-only: checkout_product_id = produto da encomenda.
        if (productOk && sellerOk && liCheckout && productId === liCheckout) {
          return true;
        }

        const { data: live } = await admin
          .from("lives")
          .select("is_active, status, seller_id")
          .eq("id", itemLive)
          .maybeSingle();
        if (liveIsActive(live) && productOk && sellerOk) return true;
      }
    }
  }

  if (liveId) {
    const { data: live } = await admin
      .from("lives")
      .select("is_active, status, seller_id")
      .eq("id", liveId)
      .maybeSingle();
    if (liveIsActive(live)) {
      const liveSeller = String(live?.seller_id ?? "").trim();
      if (!sellerId || !liveSeller || sellerId === liveSeller) {
        return true;
      }
    }
  }

  return false;
}

/**
 * C2-P2-01 fail-closed: se a order tem contexto LIVE, live_id/live_item/product
 * têm de ser coerentes (mesma regra que Postgres batata_orders_assert_live_coherence).
 * Edge não é a única defesa — trigger SQL é a autoridade.
 */
async function assertOrderLiveCoherence(
  admin: ReturnType<typeof createClient>,
  order: OrderCheckoutRow,
): Promise<void> {
  const liveItemId = String(order.live_item_id ?? "").trim();
  const liveId = String(order.live_id ?? "").trim();
  const productId = String(order.product_id ?? "").trim();
  const sellerId = String(order.seller_id ?? "").trim();

  if (!liveItemId && !liveId) return;

  if (!liveItemId && liveId) {
    const { data: live, error } = await admin
      .from("lives")
      .select("id, seller_id")
      .eq("id", liveId)
      .maybeSingle();
    if (error || !live) {
      throw new Error("Checkout blocked: live not found for order.");
    }
    const liveSeller = String(live.seller_id ?? "").trim();
    if (sellerId && liveSeller && sellerId !== liveSeller) {
      throw new Error("Checkout blocked: live seller mismatch.");
    }
    return;
  }

  const { data: li, error } = await admin
    .from("live_items")
    .select("id, live_id, seller_id, product_id, checkout_product_id")
    .eq("id", liveItemId)
    .maybeSingle();
  if (error || !li) {
    throw new Error("Checkout blocked: live item not found for order.");
  }
  const itemLive = String(li.live_id ?? "").trim();
  if (liveId && itemLive && liveId !== itemLive) {
    throw new Error("Checkout blocked: live_id does not match live_item.");
  }
  const linked = String(
    (li.product_id as string | null) ??
      (li.checkout_product_id as string | null) ??
      "",
  ).trim();
  if (productId) {
    if (!linked) {
      throw new Error("Checkout blocked: live item has no product.");
    }
    const liProd = String(li.product_id ?? "").trim();
    const liCheckout = String(li.checkout_product_id ?? "").trim();
    if (productId !== liProd && productId !== liCheckout) {
      throw new Error("Checkout blocked: live item does not match order product.");
    }
  }
  const itemSeller = String(li.seller_id ?? "").trim();
  if (sellerId && itemSeller && sellerId !== itemSeller) {
    throw new Error("Checkout blocked: live item seller mismatch.");
  }
}

function assertOrderStatusAllowsCheckout(
  status: string | null | undefined,
  forSettle: boolean,
): void {
  const st = String(status ?? "").trim().toLowerCase();
  const allowed = new Set([
    "reserva_pendente",
    "reservado",
    "aguarda_confirmacao",
    "aguarda_pagamento",
    "premio_rifa",
  ]);
  // S2-P0-01: settle replay em order já liquidada — permitir quote (sem novo checkout).
  if (forSettle) {
    for (const s of ["pago", "enviado", "entregue", "concluido", "concluído"]) {
      allowed.add(s);
    }
  }
  if (!allowed.has(st)) {
    throw new Error(
      `Checkout blocked: order status '${st || "unknown"}' cannot start payment.`,
    );
  }
}

async function loadOrderForCheckout(
  admin: ReturnType<typeof createClient>,
  orderId: string,
  buyerId: string,
  opts?: { forSettle?: boolean },
): Promise<OrderCheckoutRow> {
  const oid = orderId.trim();
  if (!oid) throw new Error("Missing order_id.");
  const forSettle = opts?.forSettle === true;
  const { data, error } = await admin
    .from("orders")
    .select(
      "id, buyer_id, seller_id, product_id, live_item_id, live_id, live_raffle_id, quantity, status, payment_method, shipping_method, stripe_payment_intent_id, stripe_checkout_session_id, stripe_refund_id, amount_paid_cents, contract_unit_cents, contract_qty, bundle_id, product_offer_id, delivery_point_ref, dpd_service, shipping_weight_kg, shipping_weight_band, shipping_weight_charged_kg, shipping_weight_charged_band, shipping_modality, shipping_cents_charged, shipping_free_by_seller, checkout_attempt_id",
    )
    .eq("id", oid)
    .maybeSingle();
  if (error || !data) {
    // Fallback sem colunas novas (cache PostgREST) — ainda fecha P1-01 via fetch extra.
    const { data: data2, error: err2 } = await admin
      .from("orders")
      .select(
        "id, buyer_id, seller_id, product_id, live_item_id, live_id, live_raffle_id, quantity, status, payment_method, shipping_method, stripe_payment_intent_id, stripe_checkout_session_id, stripe_refund_id, bundle_id",
      )
      .eq("id", oid)
      .maybeSingle();
    if (err2 || !data2) {
      throw new Error(
        `Checkout blocked: order not found.${error?.message ?? err2?.message ?? ""}`,
      );
    }
    const row2 = data2 as OrderCheckoutRow;
    if (String(row2.buyer_id ?? "") !== buyerId) {
      throw new Error("Checkout blocked: order does not belong to buyer.");
    }
    const { data: cRow } = await admin
      .from("orders")
      .select("contract_unit_cents, contract_qty")
      .eq("id", oid)
      .maybeSingle();
    if (cRow) {
      row2.contract_unit_cents = cRow.contract_unit_cents as number | null;
      row2.contract_qty = cRow.contract_qty as number | null;
    }
    assertOrderStatusAllowsCheckout(row2.status, forSettle);
    if (String(row2.stripe_refund_id ?? "").trim().length > 0) {
      throw new Error("Checkout blocked: order already refunded.");
    }
    const row2Captured = Number(row2.amount_paid_cents ?? 0);
    const row2HasPi = String(row2.stripe_payment_intent_id ?? "").trim().length > 0;
    if (!forSettle && (row2Captured > 0 || row2HasPi)) {
      throw new Error("Checkout blocked: order already captured.");
    }
    if (!forSettle && isOffPlatformPaymentMethod(row2.payment_method)) {
      throw new Error(
        "Checkout blocked: order is off-platform payment (no Stripe Session).",
      );
    }
    return row2;
  }
  const row = data as OrderCheckoutRow;
  if (String(row.buyer_id ?? "") !== buyerId) {
    throw new Error("Checkout blocked: order does not belong to buyer.");
  }

  assertOrderStatusAllowsCheckout(row.status, forSettle);
  if (
    String(row.stripe_refund_id ?? "").trim().length > 0
  ) {
    throw new Error("Checkout blocked: order already refunded.");
  }
  const capturedCents = Number(row.amount_paid_cents ?? 0);
  const hasPi = String(row.stripe_payment_intent_id ?? "").trim().length > 0;
  if (!forSettle && (capturedCents > 0 || hasPi)) {
    throw new Error("Checkout blocked: order already captured.");
  }
  // RTBB-B-2012: off-platform (MB WAY/transf/mão) ≠ Checkout Stripe.
  if (!forSettle && isOffPlatformPaymentMethod(row.payment_method)) {
    throw new Error(
      "Checkout blocked: order is off-platform payment (no Stripe Session).",
    );
  }

  return row;
}

/**
 * P1-01: preço unitário do CONTRATO da order (não catálogo vivo).
 * Fallback: se contract em falta (legado), sela a partir do catálogo actual via service
 * e usa esse valor — orders novas já vêm seladas no INSERT.
 */
async function unitPriceEurForOrder(
  admin: ReturnType<typeof createClient>,
  order: OrderCheckoutRow,
): Promise<number> {
  const sealed = Number(order.contract_unit_cents ?? 0);
  if (Number.isFinite(sealed) && sealed > 0) {
    return sealed / 100;
  }
  // Legado sem contrato: ler catálogo UMA vez e persistir (service_role).
  const productId = (order.product_id ?? "").trim();
  const liveItemId = (order.live_item_id ?? "").trim();
  let unit = 0;
  if (liveItemId.length > 0) {
    const { data: li } = await admin
      .from("live_items")
      .select("price, product_id, checkout_product_id")
      .eq("id", liveItemId)
      .maybeSingle();
    if (li) {
      const linked = String(
        (li.product_id as string | null) ??
          (li.checkout_product_id as string | null) ??
          "",
      ).trim();
      if (
        productId.length > 0 &&
        linked.length > 0 &&
        linked !== productId
      ) {
        throw new Error(
          "Checkout blocked: live item does not match order product.",
        );
      }
      unit = Number(li.price);
    }
  }
  if (!(unit > 0) && productId.length > 0) {
    const { data, error } = await admin
      .from("products")
      .select("price")
      .eq("id", productId)
      .maybeSingle();
    if (error || data?.price == null) {
      throw new Error("Checkout blocked: item without price.");
    }
    unit = Number(data.price);
  }
  if (!Number.isFinite(unit) || unit <= 0) {
    throw new Error("Checkout blocked: item without price.");
  }
  const cents = Math.max(1, Math.round(unit * 100));
  const qty = clampQty(order.contract_qty ?? order.quantity);
  await admin
    .from("orders")
    .update({ contract_unit_cents: cents, contract_qty: qty })
    .eq("id", order.id);
  order.contract_unit_cents = cents;
  order.contract_qty = qty;
  return cents / 100;
}

/** Qty autoritativa: contract_qty se selado, senão order.quantity. */
function authoritativeQty(order: OrderCheckoutRow): number {
  const cq = Number(order.contract_qty ?? 0);
  if (Number.isFinite(cq) && cq >= 1) return clampQty(cq);
  return clampQty(order.quantity);
}

/**
 * Desconto de conjunto server-side a partir de seller_bundle_discounts.
 * Espelha a lógica de escalões do Flutter (tier 2/3/5 + custom).
 */
async function bundleDiscountPercent(
  admin: ReturnType<typeof createClient>,
  sellerId: string,
  itemCount: number,
): Promise<number> {
  if (!sellerId || itemCount < 2) return 0;
  const { data } = await admin
    .from("seller_bundle_discounts")
    .select("enabled, tier_2_pct, tier_3_pct, tier_5_pct, custom_tiers")
    .eq("seller_id", sellerId)
    .maybeSingle();
  if (!data || data.enabled !== true) return 0;
  type Rule = { min_items: number; pct: number };
  const rules: Rule[] = [];
  const push = (min: number, pct: unknown) => {
    const p = Number(pct);
    if (Number.isFinite(p) && p > 0) rules.push({ min_items: min, pct: p });
  };
  push(2, data.tier_2_pct);
  push(3, data.tier_3_pct);
  push(5, data.tier_5_pct);
  const custom = data.custom_tiers;
  if (Array.isArray(custom)) {
    for (const r of custom) {
      if (r && typeof r === "object") {
        const min = Number((r as Rule).min_items);
        const pct = Number((r as Rule).pct);
        if (min >= 2 && pct > 0) rules.push({ min_items: min, pct });
      }
    }
  }
  rules.sort((a, b) => b.min_items - a.min_items);
  for (const r of rules) {
    if (itemCount >= r.min_items) return Math.min(50, r.pct);
  }
  return 0;
}

/**
 * ZIP 144.3 — montante autorizado no commerce_checkout_attempts (begin).
 * CPI e settle usam o mesmo total; portes/proteção não são recalculados.
 */
async function quoteFromCheckoutAttempt(
  admin: ReturnType<typeof createClient>,
  attemptId: string,
  buyerId: string,
  body: PaymentIntentRequest,
  forSettle: boolean,
): Promise<ServerCheckoutQuote | null> {
  const { data: att, error } = await admin
    .from("commerce_checkout_attempts")
    .select(
      "id, buyer_id, status, items_cents, shipping_cents, protection_fee_cents, total_cents, shipping_method, expires_at",
    )
    .eq("id", attemptId)
    .maybeSingle();
  if (error || !att) return null;
  if (String(att.buyer_id ?? "") !== buyerId) {
    throw new Error("Checkout blocked: attempt does not belong to buyer.");
  }
  const total = Number(att.total_cents ?? 0);
  const items = Number(att.items_cents ?? 0);
  const ship = Number(att.shipping_cents ?? 0);
  const prot = Number(att.protection_fee_cents ?? 0);
  if (!Number.isInteger(total) || total < 50) return null;

  const orderId = (body.order_id ?? "").trim();
  let order: OrderCheckoutRow | null = null;
  if (orderId) {
    order = await loadOrderForCheckout(admin, orderId, buyerId, { forSettle });
    const attOnOrder = String(
      (order as { checkout_attempt_id?: string | null }).checkout_attempt_id ??
        "",
    ).trim();
    // Soft: if order has attempt id, must match
    if (attOnOrder.length > 0 && attOnOrder !== attemptId) {
      throw new Error("Checkout blocked: order/attempt mismatch.");
    }
  } else {
    const { data: rows } = await admin
      .from("orders")
      .select(
        "id, buyer_id, seller_id, product_id, live_item_id, live_id, live_raffle_id, quantity, status, payment_method, shipping_method, stripe_payment_intent_id, stripe_checkout_session_id, stripe_refund_id, amount_paid_cents, contract_unit_cents, contract_qty, bundle_id, product_offer_id, delivery_point_ref, dpd_service, shipping_weight_kg, shipping_weight_band, shipping_weight_charged_kg, shipping_weight_charged_band, shipping_modality, shipping_cents_charged, shipping_free_by_seller, checkout_attempt_id",
      )
      .eq("checkout_attempt_id", attemptId)
      .eq("buyer_id", buyerId)
      .limit(1);
    order = (rows?.[0] as OrderCheckoutRow | undefined) ?? null;
  }
  if (!order) return null;

  // Selar portes cobrados = attempt (idempotente)
  try {
    await sealOrderShippingCharged(admin, order.id, {
      shippingCents: ship,
      weightKg: order.shipping_weight_charged_kg ?? order.shipping_weight_kg,
      band: order.shipping_weight_charged_band ?? order.shipping_weight_band,
      modality: order.shipping_modality ?? order.dpd_service,
    });
  } catch (_) { /* soft */ }

  return {
    amountCents: total,
    itemsCents: items,
    shippingCents: ship,
    protectionCents: prot,
    isPrizeShipping: false,
    authProductId: String(order.product_id ?? "").trim(),
    authSellerId: String(order.seller_id ?? "").trim(),
    authBuyerId: buyerId,
    authOrderId: order.id,
    authLiveItemId: String(order.live_item_id ?? "").trim(),
    authLiveId: String(order.live_id ?? "").trim(),
    lineQuotes: [],
  };
}

/**
 * P0-01 trust boundary: ORDER → contexto → preço.
 * Body pode identificar order_id / shipping_method / bag order ids;
 * product_id, live_item_id, prize_shipping, qty, seller, line_total NÃO mandam no total.
 */
async function resolveServerCheckoutQuote(
  admin: ReturnType<typeof createClient>,
  body: PaymentIntentRequest,
  isBagCheckout: boolean,
  bagLines: BagCheckoutLine[],
  buyerId: string,
  /** Settle pós-captura: validar montante sem stock gate (oversell → refund no settle). */
  opts?: { forSettle?: boolean },
): Promise<ServerCheckoutQuote> {
  const forSettle = opts?.forSettle === true;

  const assertClientIdsMatchOrder = (order: OrderCheckoutRow) => {
    const claimedProduct = (body.product_id ?? "").trim();
    if (
      claimedProduct.length > 0 &&
      claimedProduct !== String(order.product_id ?? "").trim()
    ) {
      throw new Error("Checkout blocked: product does not match order.");
    }
    const claimedLive = (body.live_item_id ?? "").trim();
    const orderLive = String(order.live_item_id ?? "").trim();
    if (claimedLive.length > 0) {
      if (orderLive.length === 0 || claimedLive !== orderLive) {
        throw new Error("Checkout blocked: live item does not match order.");
      }
    }
    const claimedSeller = (body.seller_id ?? "").trim();
    if (
      claimedSeller.length > 0 &&
      claimedSeller !== String(order.seller_id ?? "").trim()
    ) {
      throw new Error("Checkout blocked: seller does not match order.");
    }
  };

  // ZIP 144.3: attempt congelado = montante autorizado (begin → CPI → settle).
  const attemptId = String(body.checkout_attempt_id ?? "").trim();
  if (attemptId.length > 0 && !isBagCheckout) {
    const fromAttempt = await quoteFromCheckoutAttempt(
      admin,
      attemptId,
      buyerId,
      body,
      forSettle,
    );
    if (fromAttempt) return fromAttempt;
  }

  // --- Single order ---
  if (!isBagCheckout) {
    const orderId = (body.order_id ?? "").trim();
    const order = await loadOrderForCheckout(admin, orderId, buyerId, {
      forSettle,
    });
    assertClientIdsMatchOrder(order);
    await assertOrderLiveCoherence(admin, order);

    // B-SHIP-CLIENT / RTC-C-P2-SHIP: selo + Pickup/peso DPD (Célia).
    let shippingCents: number;
    const bodyShipExtras = {
      shipping_weight_kg: (body as { shipping_weight_kg?: number })
        .shipping_weight_kg,
      shipping_weight_band: (body as { shipping_weight_band?: string })
        .shipping_weight_band,
      shipping_modality: (body as { shipping_modality?: string })
        .shipping_modality,
    };
    try {
      shippingCents = resolveOrderShippingCents(
        order as OrderShipCtx,
        body.shipping_method,
        bodyShipExtras,
      );
    } catch (_) {
      throw new Error(
        "Checkout blocked: portes da encomenda inválidos.",
      );
    }
    // Selo para reconciliação (não confiar só no body após pago).
    try {
      const hasPickup =
        String(order.delivery_point_ref ?? "").trim().length > 0;
      const modality = String(
        bodyShipExtras.shipping_modality ??
          order.dpd_service ??
          (hasPickup ? "shop_to_shop" : "shop_to_home"),
      );
      await sealOrderShippingCharged(admin, order.id, {
        shippingCents,
        weightKg: bodyShipExtras.shipping_weight_kg ??
          order.shipping_weight_kg,
        band: bodyShipExtras.shipping_weight_band ??
          order.shipping_weight_band,
        modality,
      });
    } catch (sealErr) {
      console.warn("sealOrderShippingCharged soft-fail", sealErr);
    }

    const wantsPrize = body.prize_shipping === true;
    const isPrize = await isAuthoritativePrizeOrder(admin, order, buyerId);
    if (wantsPrize && !isPrize) {
      throw new Error("Checkout blocked: order is not a raffle prize.");
    }

    if (isPrize) {
      if (shippingCents < 50) {
        throw new Error("Invalid prize shipping amount.");
      }
      const prot = protectionFeeCents(0, shippingCents);
      const amountCents = shippingCents + prot;
      if (amountCents < 50) throw new Error("Invalid payment amount.");
      return {
        amountCents,
        itemsCents: 0,
        shippingCents,
        protectionCents: prot,
        isPrizeShipping: true,
        authProductId: String(order.product_id ?? "").trim(),
        authSellerId: String(order.seller_id ?? "").trim(),
        authBuyerId: buyerId,
        authOrderId: order.id,
        authLiveItemId: String(order.live_item_id ?? "").trim(),
        authLiveId: String(order.live_id ?? "").trim(),
        lineQuotes: [],
      };
    }

    const unit = await unitPriceEurForOrder(admin, order);
    const qty = authoritativeQty(order);
    // E6-P1 / RTBB-B-01: stock efectivo = quantity - holds; is_sold bloqueia.
    // Settle (forSettle): sem stock gate — oversell → refund.
    if (order.product_id && !forSettle) {
      const { data: productGate } = await admin
        .from("products")
        .select("is_sold, list_on_marketplace")
        .eq("id", order.product_id)
        .maybeSingle();
      if (productGate?.is_sold === true) {
        throw new Error("Checkout blocked: product is marked sold.");
      }
      // RTI4-1916: unlist só com live ACTIVA (não ended / não raffle JWT).
      if (
        productGate?.list_on_marketplace === false &&
        !(await orderHasActiveLiveUnlistBypass(admin, order))
      ) {
        throw new Error("Checkout blocked: product is not listed.");
      }
      const { data: stockCheck, error: stockErr } = await admin.rpc(
        "batata_product_checkout_available",
        {
          p_product_id: order.product_id,
          p_exclude_order_id: order.id,
          p_need_qty: qty,
        },
      );
      if (stockErr) {
        throw new Error(
          `Checkout blocked: stock check failed (${stockErr.message}).`,
        );
      }
      const sc = stockCheck as {
        ok?: boolean;
        available?: number;
        stock?: number;
        need?: number;
      } | null;
      if (!sc || sc.ok !== true) {
        const avail = Number(sc?.available ?? 0);
        throw new Error(
          `Checkout blocked: quantity ${qty} exceeds available stock ${avail}.`,
        );
      }
    }
    const lineItemsCents = euroToCents(unit * qty);
    if (lineItemsCents < 50) {
      throw new Error("Checkout blocked: item without price.");
    }
    const prot = protectionFeeCents(lineItemsCents, shippingCents);
    const amountCents = lineItemsCents + shippingCents + prot;
    if (!Number.isInteger(amountCents) || amountCents < 50) {
      throw new Error("Invalid payment amount.");
    }
    return {
      amountCents,
      itemsCents: lineItemsCents,
      shippingCents,
      protectionCents: prot,
      isPrizeShipping: false,
      authProductId: String(order.product_id ?? "").trim(),
      authSellerId: String(order.seller_id ?? "").trim(),
      authBuyerId: buyerId,
      authOrderId: order.id,
      authLiveItemId: String(order.live_item_id ?? "").trim(),
      authLiveId: String(order.live_id ?? "").trim(),
      lineQuotes: [{
        order_id: order.id,
        product_id: String(order.product_id ?? "").trim(),
        live_item_id: String(order.live_item_id ?? "").trim(),
        quantity: qty,
        unit_eur: unit,
        line_items_cents: lineItemsCents,
      }],
    };
  }

  // --- Bag / bundle ---
  if (bagLines.length === 0) {
    throw new Error("Checkout blocked: empty bag.");
  }
  if (body.prize_shipping === true) {
    throw new Error("Checkout blocked: prize shipping cannot be bag checkout.");
  }
  // BI-SHIP-01: bag — portes = max DPD Célia por linha (Pickup/peso); body se sem selo.
  let shippingCents = 0;
  let anySealedShip = false;
  for (const line of bagLines) {
    const oidPeek = String(line.order_id ?? "").trim();
    if (!oidPeek) continue;
    try {
      const oPeek = await loadOrderForCheckout(admin, oidPeek, buyerId, {
        forSettle,
      });
      const sealed = String(oPeek.shipping_method ?? "").trim();
      if (sealed.length > 0) {
        try {
          const c = resolveOrderShippingCents(
            oPeek as OrderShipCtx,
            body.shipping_method,
            {
              shipping_weight_kg: (body as { shipping_weight_kg?: number })
                .shipping_weight_kg,
              shipping_weight_band:
                (body as { shipping_weight_band?: string })
                  .shipping_weight_band,
              shipping_modality: (body as { shipping_modality?: string })
                .shipping_modality,
            },
          );
          shippingCents = Math.max(shippingCents, c);
          anySealedShip = true;
          try {
            await sealOrderShippingCharged(admin, oidPeek, {
              shippingCents: c,
              weightKg: (body as { shipping_weight_kg?: number })
                .shipping_weight_kg ?? oPeek.shipping_weight_kg,
              band: (body as { shipping_weight_band?: string })
                .shipping_weight_band ?? oPeek.shipping_weight_band,
              modality: (body as { shipping_modality?: string })
                .shipping_modality ?? oPeek.dpd_service,
            });
          } catch (_) { /* soft */ }
        } catch (_) {
          throw new Error(
            "Checkout blocked: portes da encomenda inválidos.",
          );
        }
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes("portes da encomenda inválidos")) throw e;
      /* load falha mais abaixo */
    }
  }
  if (!anySealedShip) {
    shippingCents = shippingCentsFromMethod(body.shipping_method);
  }

  const lineQuotes: ServerCheckoutQuote["lineQuotes"] = [];
  let authSellerId = "";
  let authProductId = "";
  let authOrderId = "";
  let authLiveItemId = "";
  let authLiveId = "";
  const bundleIds = new Set<string>();
  let anyNegotiatedOffer = false;

  for (const line of bagLines) {
    const oid = (line.order_id ?? "").trim();
    if (!oid) {
      throw new Error("Checkout blocked: bag line missing order_id.");
    }
    const order = await loadOrderForCheckout(admin, oid, buyerId, {
      forSettle,
    });
    await assertOrderLiveCoherence(admin, order);
    if (await isAuthoritativePrizeOrder(admin, order, buyerId)) {
      throw new Error("Checkout blocked: prize order cannot be in bag.");
    }

    // Se o cliente enviou IDs na line, têm de coincidir com a order.
    const lineProduct = (line.product_id ?? "").trim();
    if (
      lineProduct.length > 0 &&
      lineProduct !== String(order.product_id ?? "").trim()
    ) {
      throw new Error("Checkout blocked: bag product does not match order.");
    }
    const lineLive = (line.live_item_id ?? "").trim();
    const orderLive = String(order.live_item_id ?? "").trim();
    if (lineLive.length > 0 && (orderLive.length === 0 || lineLive !== orderLive)) {
      throw new Error("Checkout blocked: bag live item does not match order.");
    }
    const lineSeller = (line.seller_id ?? "").trim();
    const orderSeller = String(order.seller_id ?? "").trim();
    if (!orderSeller) {
      throw new Error("Checkout blocked: bag order missing seller.");
    }
    if (lineSeller.length > 0 && lineSeller !== orderSeller) {
      throw new Error("Checkout blocked: bag seller does not match order.");
    }

    const bundleId = String(order.bundle_id ?? "").trim();
    if (bundleId.length > 0) bundleIds.add(bundleId);
    const sealedContract = Number(order.contract_unit_cents ?? 0);
    const offerId = String(order.product_offer_id ?? "").trim();
    // AN-P3-02: selo de catálogo ≠ oferta negociada; tier do saco só bloqueia ofertas
    if (offerId.length > 0 && Number.isFinite(sealedContract) && sealedContract > 0) {
      anyNegotiatedOffer = true;
    }

    // SAT-BAG-01 / SATI-BAG-MS-01: 1 bag Checkout Session = 1 seller (produto).
    // UI já bloqueia; Edge fail-closed antes de criar Session / alterar totais.
    if (!authSellerId) {
      authSellerId = orderSeller;
      authOrderId = order.id;
      authProductId = String(order.product_id ?? "").trim();
      authLiveItemId = orderLive;
      authLiveId = String(order.live_id ?? "").trim();
    } else if (orderSeller !== authSellerId) {
      throw new Error(
        "Checkout blocked: bag lines must share one seller. Pay each seller separately.",
      );
    }

    const unit = await unitPriceEurForOrder(admin, order);
    const qty = authoritativeQty(order);
    if (order.product_id) {
      const { data: stockRow } = await admin
        .from("products")
        .select("quantity, seller_id, is_sold, list_on_marketplace")
        .eq("id", order.product_id)
        .maybeSingle();
      if (
        stockRow?.seller_id &&
        order.seller_id &&
        String(stockRow.seller_id) !== String(order.seller_id)
      ) {
        throw new Error(
          "Checkout blocked: order seller does not own product.",
        );
      }
      // E6-BAG-UNLIST: mesmo gate que single (unlist/sold). Settle: sem gate.
      if (!forSettle) {
        if (stockRow?.is_sold === true) {
          throw new Error("Checkout blocked: product is marked sold.");
        }
        // RTI4-1916: mesmo gate bag — unlist só live ACTIVA.
        if (
          stockRow?.list_on_marketplace === false &&
          !(await orderHasActiveLiveUnlistBypass(admin, order))
        ) {
          throw new Error("Checkout blocked: product is not listed.");
        }
        const { data: stockCheck, error: stockErr } = await admin.rpc(
          "batata_product_checkout_available",
          {
            p_product_id: order.product_id,
            p_exclude_order_id: order.id,
            p_need_qty: qty,
          },
        );
        if (stockErr) {
          throw new Error(
            `Checkout blocked: stock check failed (${stockErr.message}).`,
          );
        }
        const sc = stockCheck as {
          ok?: boolean;
          available?: number;
        } | null;
        if (!sc || sc.ok !== true) {
          const avail = Number(sc?.available ?? 0);
          throw new Error(
            `Checkout blocked: quantity ${qty} exceeds available stock ${avail}.`,
          );
        }
      }
    }
    const lineItemsCents = euroToCents(unit * qty);
    lineQuotes.push({
      order_id: order.id,
      product_id: String(order.product_id ?? "").trim(),
      live_item_id: orderLive,
      quantity: qty,
      unit_eur: unit,
      line_items_cents: lineItemsCents,
    });
  }

  // Mesmo SKU no saco: somar qty pedida vs stock (captura evitável se já se sabe).
  // Não muda corridas paralelas entre requests — só o mesmo bag quote.
  const qtyByProduct = new Map<string, number>();
  for (const lq of lineQuotes) {
    const pid = (lq.product_id ?? "").trim();
    if (!pid) continue;
    qtyByProduct.set(pid, (qtyByProduct.get(pid) ?? 0) + lq.quantity);
  }
  for (const [pid, need] of qtyByProduct) {
    if (forSettle) break;
    // Excluir todas as linhas do saco deste SKU do held (não só uma).
    const bagOrderIds = lineQuotes
      .filter((lq) => (lq.product_id ?? "").trim() === pid)
      .map((lq) => lq.order_id);
    const { data: stockCheck, error: stockErr } = await admin.rpc(
      "batata_product_checkout_available",
      {
        p_product_id: pid,
        p_exclude_order_id: bagOrderIds[0] ?? null,
        p_need_qty: need,
        p_exclude_order_ids: bagOrderIds,
      },
    );
    if (stockErr) {
      throw new Error(
        `Checkout blocked: stock check failed (${stockErr.message}).`,
      );
    }
    const sc = stockCheck as { ok?: boolean; available?: number } | null;
    if (!sc || sc.ok !== true) {
      const avail = Number(sc?.available ?? 0);
      throw new Error(
        `Checkout blocked: quantity ${need} exceeds available stock ${avail}.`,
      );
    }
  }

  let itemsCents = lineQuotes.reduce((s, l) => s + l.line_items_cents, 0);
  // RTU-U2 + RTV-V4: conjunto aceite → total_eur; saco exacto (sem SKU extra).
  let useAcceptedBundleTotal = false;
  if (bundleIds.size > 1) {
    throw new Error(
      "Checkout blocked: bag cannot mix multiple bundle contracts.",
    );
  }
  if (bundleIds.size === 1) {
    const bundleId = [...bundleIds][0];
    const { data: bundleRow } = await admin
      .from("product_bundles")
      .select(
        "status, total_eur, product_ids, buyer_id, articles_cents, grand_total_cents, rule_version",
      )
      .eq("id", bundleId)
      .maybeSingle();
    const bundleBuyerId = String(bundleRow?.buyer_id ?? "").trim();
    if (bundleBuyerId.length > 0 && bundleBuyerId !== buyerId.trim()) {
      throw new Error(
        "Checkout blocked: bundle contract belongs to another buyer.",
      );
    }
    const bundleStatus = String(bundleRow?.status ?? "").trim().toLowerCase();
    // ZIP149: awaiting_payment = cotação confirmada (sem hold); accepted = legado.
    const bundlePayable = bundleStatus === "awaiting_payment" ||
      bundleStatus === "accepted";
    const sealedArticles = Number(bundleRow?.articles_cents ?? 0);
    const sealedGrand = Number(bundleRow?.grand_total_cents ?? 0);
    const bundleTotal = sealedArticles > 0
      ? sealedArticles / 100
      : Number(bundleRow?.total_eur ?? 0);
    const bundleProductIds = (Array.isArray(bundleRow?.product_ids)
      ? bundleRow.product_ids
      : [])
      .map((id: unknown) => String(id ?? "").trim())
      .filter((id: string) => id.length > 0);
    const bagLinesWithProduct = lineQuotes.filter((lq) =>
      (lq.product_id ?? "").trim().length > 0
    );
    const bagProductIds = new Set(
      bagLinesWithProduct.map((lq) => (lq.product_id ?? "").trim()),
    );
    // Multiset: contar ocorrências, não só IDs únicos.
    const countIds = (ids: string[]) => {
      const m = new Map<string, number>();
      for (const id of ids) m.set(id, (m.get(id) ?? 0) + 1);
      return m;
    };
    const bundleCounts = countIds(bundleProductIds);
    const bagCounts = new Map<string, number>();
    for (const lq of bagLinesWithProduct) {
      const pid = (lq.product_id ?? "").trim();
      bagCounts.set(pid, (bagCounts.get(pid) ?? 0) + Math.max(1, lq.quantity));
    }
    const bundleComplete = bundleProductIds.length > 0 &&
      bundleCounts.size === bagCounts.size &&
      [...bundleCounts.entries()].every(([id, n]) => bagCounts.get(id) === n);
    if (bundlePayable && Number.isFinite(bundleTotal) && bundleTotal > 0 &&
      !bundleComplete
    ) {
      throw new Error(
        "Checkout blocked: bag must include all items in the accepted bundle.",
      );
    }
    if (
      bundlePayable && Number.isFinite(bundleTotal) && bundleTotal > 0 &&
      bundleComplete
    ) {
      const bundleTotalCents = sealedArticles > 0
        ? sealedArticles
        : euroToCents(bundleTotal);
      if (bundleTotalCents >= 50) {
        useAcceptedBundleTotal = true;
        const origSum = itemsCents;
        let allocated = 0;
        for (let i = 0; i < lineQuotes.length; i++) {
          const lq = lineQuotes[i];
          if (i === lineQuotes.length - 1) {
            lq.line_items_cents = Math.max(0, bundleTotalCents - allocated);
          } else {
            const share = origSum > 0
              ? Math.round((bundleTotalCents * lq.line_items_cents) / origSum)
              : Math.round(bundleTotalCents / lineQuotes.length);
            lq.line_items_cents = share;
            allocated += share;
          }
        }
        itemsCents = bundleTotalCents;
      }
      // Montante Stripe total = grand_total selado quando rule_version ZIP149.
      if (
        String(bundleRow?.rule_version ?? "") === "quote_before_pay_v1" &&
        sealedGrand >= 50
      ) {
        // articles já em itemsCents; portes+proteção vêm do attempt/seal a jusante.
        void sealedGrand;
      }
    }
  }
  // P1-01 conjunto: desconto tier só se não há contrato de conjunto aceite nem ofertas negociadas.
  const itemCount = lineQuotes.reduce((s, l) => s + l.quantity, 0);
  if (!useAcceptedBundleTotal && !anyNegotiatedOffer) {
    const discPct = await bundleDiscountPercent(admin, authSellerId, itemCount);
    if (discPct > 0 && itemsCents > 0) {
      const discounted = Math.round(itemsCents * (1 - discPct / 100));
      // Redistribuir line_items_cents proporcionalmente ao desconto
      let allocated = 0;
      for (let i = 0; i < lineQuotes.length; i++) {
        const lq = lineQuotes[i];
        if (i === lineQuotes.length - 1) {
          lq.line_items_cents = Math.max(0, discounted - allocated);
        } else {
          const share = Math.round(
            (discounted * lq.line_items_cents) / itemsCents,
          );
          lq.line_items_cents = share;
          allocated += share;
        }
      }
      itemsCents = discounted;
    }
  }
  if (itemsCents < 50) {
    throw new Error("Checkout blocked: item without price.");
  }
  const prot = protectionFeeCents(itemsCents, shippingCents);
  const amountCents = itemsCents + shippingCents + prot;
  if (!Number.isInteger(amountCents) || amountCents < 50) {
    throw new Error("Invalid payment amount.");
  }
  return {
    amountCents,
    itemsCents,
    shippingCents,
    protectionCents: prot,
    isPrizeShipping: false,
    authProductId,
    authSellerId,
    authBuyerId: buyerId,
    authOrderId,
    authLiveItemId,
    authLiveId,
    lineQuotes,
  };
}

function parseBagCheckoutLines(
  sessionMetadata: Record<string, string> | null | undefined,
): BagCheckoutLine[] {
  const meta = sessionMetadata ?? {};
  const legacyJson = meta.bag_orders_json?.trim() ?? "";
  if (legacyJson.length > 0) {
    try {
      const parsed = JSON.parse(legacyJson) as BagCheckoutLine[];
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    } catch (_) {
      /* fallback compact keys */
    }
  }

  const orderIds = (meta.bag_order_ids ?? "")
    .split(",")
    .map((s) => hydrateCompactUuid(s.trim()))
    .filter((s) => s.length > 0);
  const productIds = (meta.bag_product_ids ?? "")
    .split(",")
    .map((s) => hydrateCompactUuid(s.trim()));
  const itemIds = (meta.bag_live_item_ids ?? "")
    .split(",")
    .map((s) => hydrateCompactUuid(s.trim()));
  const requestIds = (meta.bag_request_ids ?? "")
    .split(",")
    .map((s) => hydrateCompactUuid(s.trim()));

  return orderIds.map((orderId, i) => ({
    order_id: orderId,
    product_id: productIds[i] ?? "",
    live_item_id: itemIds[i] ?? "",
    reservation_request_id: requestIds[i] ?? "",
  }));
}

function compactBagStripeMetadata(
  bagLines: BagCheckoutLine[],
): Record<string, string> {
  const orderIds: string[] = [];
  const productIds: string[] = [];
  const itemIds: string[] = [];
  const requestIds: string[] = [];
  for (const line of bagLines) {
    const oid = line.order_id?.trim() ?? "";
    if (!oid) continue;
    // AN-P3-01: Stripe metadata value ≤500 chars — UUID sem hífens
    orderIds.push(oid.replace(/-/g, ""));
    productIds.push((line.product_id?.trim() ?? "").replace(/-/g, ""));
    itemIds.push((line.live_item_id?.trim() ?? "").replace(/-/g, ""));
    requestIds.push((line.reservation_request_id?.trim() ?? "").replace(/-/g, ""));
  }
  const meta = {
    bag_checkout: "true",
    bag_order_ids: orderIds.join(","),
    bag_product_ids: productIds.join(","),
    bag_live_item_ids: itemIds.join(","),
    bag_request_ids: requestIds.join(","),
  };
  for (const [k, v] of Object.entries(meta)) {
    if (k === "bag_checkout") continue;
    if (v.length > 500) {
      throw new Error(
        "Checkout blocked: bag too large for payment metadata. Split the bag.",
      );
    }
  }
  return meta;
}

function hydrateCompactUuid(raw: string): string {
  const s = raw.trim();
  if (/^[0-9a-fA-F]{32}$/.test(s)) {
    return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
  }
  return s;
}

/** AT/AZ: comparar bag_order_ids compactos vs hífenados como o mesmo conjunto. */
function normalizeBagOrderIdsKey(csvOrList: string | string[]): string {
  const parts = Array.isArray(csvOrList)
    ? csvOrList
    : String(csvOrList ?? "").split(",");
  return parts
    .map((s) => hydrateCompactUuid(s.trim()).replace(/-/g, "").toLowerCase())
    .filter((s) => s.length > 0)
    .sort()
    .join(",");
}

function bagIdSetFromKey(key: string): Set<string> {
  return new Set(key.split(",").filter(Boolean));
}

/** prior cobre current (todo id de current está em prior). */
function bagSetCovers(priorKey: string, currentKey: string): boolean {
  const prior = bagIdSetFromKey(priorKey);
  const current = bagIdSetFromKey(currentKey);
  if (current.size === 0) return false;
  for (const id of current) {
    if (!prior.has(id)) return false;
  }
  return true;
}

function bagSetsOverlap(aKey: string, bKey: string): boolean {
  const a = bagIdSetFromKey(aKey);
  const b = bagIdSetFromKey(bKey);
  for (const id of a) {
    if (b.has(id)) return true;
  }
  return false;
}

async function expireSharedBagCheckoutSession(
  stripe: Stripe,
  supabaseAdmin: ReturnType<typeof createClient>,
  prior: Stripe.Checkout.Session,
): Promise<void> {
  const bagIds = String(prior.metadata?.bag_order_ids ?? "")
    .split(",")
    .map((s) => hydrateCompactUuid(s.trim()))
    .filter(Boolean);
  const orderId = hydrateCompactUuid(
    String(prior.metadata?.order_id ?? "").trim(),
  );
  const clearIds = bagIds.length > 0
    ? bagIds
    : (orderId.length > 0 ? [orderId] : []);
  try {
    if (prior.status === "open") {
      await stripe.checkout.sessions.expire(prior.id);
    }
  } catch (e) {
    console.error("expireSharedBagCheckoutSession", prior.id, e);
  }
  for (const oid of clearIds) {
    await supabaseAdmin
      .from("orders")
      .update({ stripe_checkout_session_id: null })
      .eq("id", oid)
      .eq("stripe_checkout_session_id", prior.id);
  }
}

const BAG_PENDING_STATUSES = [
  "reserva_pendente",
  "reservado",
  "aguarda_confirmacao",
  "aguarda_pagamento",
  "premio_rifa",
] as const;

/**
 * OPEN: Session de saco (metadata) inclui esta order?
 * Compara UUIDs compactos e com hífen.
 */
function bagSessionIncludesOrder(
  prior: Stripe.Checkout.Session,
  orderId: string,
): boolean {
  const oid = (orderId ?? "").trim();
  if (!oid) return false;
  const bagKey = normalizeBagOrderIdsKey(
    String(prior.metadata?.bag_order_ids ?? ""),
  );
  if (bagKey.length > 0) {
    const set = bagIdSetFromKey(bagKey);
    const compact = normalizeBagOrderIdsKey(oid);
    if (set.has(oid) || (compact.length > 0 && set.has(compact))) return true;
    for (const id of set) {
      if (hydrateCompactUuid(id) === oid || id === hydrateCompactUuid(oid)) {
        return true;
      }
    }
  }
  const metaOid = hydrateCompactUuid(
    String(prior.metadata?.order_id ?? "").trim(),
  );
  return metaOid === oid;
}
async function expireOverlappingOpenSessionsForBuyer(
  stripe: Stripe,
  supabaseAdmin: ReturnType<typeof createClient>,
  buyerId: string,
  keepSid: string,
  bagOrderIds: string[],
): Promise<void> {
  if (!buyerId || !keepSid.startsWith("cs_") || bagOrderIds.length < 1) return;
  const currentBag = normalizeBagOrderIdsKey(bagOrderIds);
  const bagSet = new Set(bagOrderIds);
  const { data: rows } = await supabaseAdmin
    .from("orders")
    .select("id, stripe_checkout_session_id")
    .eq("buyer_id", buyerId)
    .in("status", [...BAG_PENDING_STATUSES])
    .not("stripe_checkout_session_id", "is", null);
  const otherSids = new Set<string>();
  for (const row of rows ?? []) {
    const sid = String(row.stripe_checkout_session_id ?? "").trim();
    if (!sid.startsWith("cs_") || sid === keepSid) continue;
    otherSids.add(sid);
  }
  for (const sid of otherSids) {
    try {
      const prior = await stripe.checkout.sessions.retrieve(sid);
      if (prior.status !== "open" || prior.payment_status === "paid") continue;
      const priorBag = normalizeBagOrderIdsKey(
        String(prior.metadata?.bag_order_ids ?? ""),
      );
      const priorOid = hydrateCompactUuid(
        String(prior.metadata?.order_id ?? "").trim(),
      );
      const touchesBag = (rows ?? []).some((r) =>
        String(r.stripe_checkout_session_id ?? "").trim() === sid &&
        bagSet.has(String(r.id ?? ""))
      );
      const overlapsMeta =
        (priorBag.length > 0 && bagSetsOverlap(priorBag, currentBag)) ||
        (priorOid.length > 0 && bagSet.has(priorOid));
      if (!touchesBag && !overlapsMeta) continue;
      // Saco maior que nos cobre → manter (reuse); nós somos o subset
      if (
        priorBag.length > 0 &&
        bagSetCovers(priorBag, currentBag) &&
        priorBag !== currentBag
      ) {
        continue;
      }
      await expireSharedBagCheckoutSession(stripe, supabaseAdmin, prior);
    } catch (e) {
      console.error("expireOverlappingOpenSessionsForBuyer", sid, e);
    }
  }
}

async function resolveBagLineLabels(
  supabase: ReturnType<typeof createClient>,
  lines: BagCheckoutLine[],
): Promise<string[]> {
  const labels: string[] = [];
  for (const line of lines) {
    const fromMeta = (line.item_label ?? "").trim();
    if (
      fromMeta.length > 0 &&
      fromMeta !== "Artigo" &&
      fromMeta !== "Artigo Fleaber"
    ) {
      labels.push(fromMeta);
      continue;
    }
    const pid = line.product_id?.trim() ?? "";
    if (!pid) {
      labels.push("Artigo");
      continue;
    }
    const { data } = await supabase
      .from("products")
      .select("title")
      .eq("id", pid)
      .maybeSingle();
    const title = (data?.title as string | undefined)?.trim() ?? "";
    labels.push(title.length > 0 ? title : "Artigo");
  }
  return labels;
}

async function sendMarketplaceBagPaidChatMessage(
  supabase: ReturnType<typeof createClient>,
  buyerId: string,
  sellerId: string,
  lines: BagCheckoutLine[],
  totalCents: number,
) {
  if (lines.length === 0) return;
  const firstProductId = lines[0]?.product_id?.trim() ?? "";
  if (!firstProductId) return;

  const labels = await resolveBagLineLabels(supabase, lines);
  const count = lines.length;
  const totalText =
    Number.isFinite(totalCents) && totalCents > 0
      ? ` (${(totalCents / 100).toFixed(2).replace(".", ",")} €)`
      : "";

  let text: string;
  if (count > 1) {
    // Card «Comprado!» injectado no cliente — payload oculto na timeline.
    text = `FLEABER_JSON_V1:${JSON.stringify({
      kind: "marketplace_bag_paid",
      v: 1,
      line_count: count,
      total_cents: totalCents,
      lines: lines.map((l, i) => ({
        product_id: l.product_id,
        item_label: labels[i] ?? "Artigo",
      })),
    })}`;
  } else {
    const label = labels[0] ?? "Artigo";
    // Sem UUID na bolha — o cliente mostra card «Comprado!».
    text = `Compra paga através do Seguro Fleaber: ${label}${totalText}.`;
  }

  try {
    // CHAT-MULTI: cada pagamento de saco → chat NOVO (não thread antiga).
    const firstLine = lines[0];
    const { data: newChat } = await supabase
      .from("chats")
      .insert({
        user_a: buyerId,
        user_b: sellerId,
        product_id: firstProductId,
      })
      .select("id")
      .single();
    const chatId = (newChat?.id ?? "").trim();
    if (!chatId) return;

    const { data: existingPlain } = await supabase
      .from("chat_messages")
      .select("id")
      .eq("chat_id", chatId)
      .like("text", "Compra%conjunto paga através do Seguro Fleaber%")
      .limit(1)
      .maybeSingle();
    const { data: existingJson } = await supabase
      .from("chat_messages")
      .select("id")
      .eq("chat_id", chatId)
      .like("text", "FLEABER_JSON_V1:%marketplace_bag_paid%")
      .limit(1)
      .maybeSingle();
    const existingMessage = existingPlain ?? existingJson;

    if (!existingMessage) {
      await supabase.from("chat_messages").insert({
        sender_id: buyerId,
        receiver_id: sellerId,
        chat_id: chatId,
        text,
        is_read: false,
        is_reservation: false,
      });
    }

    await supabase
      .from("chats")
      .update({
        last_message: "Compra paga pelo Seguro Fleaber",
        last_message_time: new Date().toISOString(),
      })
      .eq("id", chatId);

    await logStripeCheckoutEvent(supabase, "chat_multi_bag_v5", {
      buyer_id: buyerId,
      seller_id: sellerId,
      product_id: firstProductId,
      chat_id: chatId,
      line_count: lines.length,
      first_order_id: firstLine?.order_id ?? null,
    });
  } catch (chatError) {
    console.error("Fleaber bag chat update failed", chatError);
  }
}

function stripeIdsFromSession(session: {
  id?: string;
  payment_intent?: string | { id?: string } | null;
}): { sessionId: string; paymentIntentId: string } {
  const sessionId = (session.id ?? "").trim();
  const pi = session.payment_intent;
  const paymentIntentId = typeof pi === "string"
    ? pi.trim()
    : (pi?.id ?? "").trim();
  return { sessionId, paymentIntentId };
}

/** RTBB-1115-P1: Session paga pode adiar PI — expand / re-retrieve. */
async function resolveCheckoutPaymentIntentId(
  stripe: Stripe,
  session: {
    id?: string;
    payment_intent?: string | { id?: string } | null;
  },
): Promise<string> {
  const first = stripeIdsFromSession(session).paymentIntentId;
  if (first.length > 0) return first;
  const sid = (session.id ?? "").trim();
  if (!sid) return "";
  try {
    const full = await stripe.checkout.sessions.retrieve(sid, {
      expand: ["payment_intent"],
    });
    return stripeIdsFromSession(full).paymentIntentId;
  } catch (_) {
    return "";
  }
}

/**
 * RTBB-1115-P1: 2.ª Session paga na mesma order — reembolsa SÓ esse PI.
 * Não cancela a venda nem grava stripe_refund_id da order (esse é do PI legítimo).
 */
async function refundOrphanDuplicatePaymentIntent(opts: {
  stripe: Stripe;
  supabase: ReturnType<typeof createClient>;
  orderId: string;
  paymentIntentId: string;
  sessionId?: string;
  reason: string;
}): Promise<{ refundId: string | null; already: boolean }> {
  const pi = opts.paymentIntentId.trim();
  if (!pi) return { refundId: null, already: false };
  try {
    const listed = await opts.stripe.refunds.list({
      payment_intent: pi,
      limit: 10,
    });
    const existing = listed.data.find((r) => {
      const st = String(r.status ?? "").toLowerCase();
      return st === "succeeded" || st === "pending" || st === "requires_action";
    });
    if (existing) {
      await logStripeCheckoutEvent(opts.supabase, "sec_dup_session_pi_already_refunded", {
        order_id: opts.orderId,
        session_id: opts.sessionId ?? null,
        payment_intent: pi,
        refund_id: existing.id,
        reason: opts.reason,
      });
      return { refundId: existing.id, already: true };
    }
    const refund = await opts.stripe.refunds.create(
      {
        payment_intent: pi,
        reason: "duplicate",
        metadata: {
          fleaber_order_id: opts.orderId,
          fleaber_reason: opts.reason,
          fleaber_session_id: opts.sessionId ?? "",
        },
      },
      { idempotencyKey: `fleaber_dup_pay_refund_${pi}` },
    );
    await logStripeCheckoutEvent(opts.supabase, "sec_dup_session_pi_refunded", {
      order_id: opts.orderId,
      session_id: opts.sessionId ?? null,
      payment_intent: pi,
      refund_id: refund.id,
      reason: opts.reason,
    });
    console.warn(
      `BATATA_DUP_PAY refunded pi=${pi} order=${opts.orderId} reason=${opts.reason}`,
    );
    return { refundId: refund.id, already: false };
  } catch (e) {
    console.error("BATATA_DUP_PAY refund_failed", opts.orderId, pi, e);
    await logStripeCheckoutEvent(opts.supabase, "sec_dup_session_pi_refund_failed", {
      order_id: opts.orderId,
      session_id: opts.sessionId ?? null,
      payment_intent: pi,
      error: e instanceof Error ? e.message : String(e),
      reason: opts.reason,
    });
    return { refundId: null, already: false };
  }
}

function isOrderLiquidatedStatus(status: string | null | undefined): boolean {
  const st = String(status ?? "").toLowerCase();
  return (
    st === "pago" ||
    st === "enviado" ||
    st === "entregue" ||
    st === "concluido" ||
    st === "concluído"
  );
}

function isStockInsufficientError(error: unknown): boolean {
  const msg = error instanceof Error
    ? error.message
    : typeof error === "object" && error && "message" in error
    ? String((error as { message?: unknown }).message ?? "")
    : String(error ?? "");
  const code = typeof error === "object" && error && "code" in error
    ? String((error as { code?: unknown }).code ?? "")
    : "";
  return code === "P0001" || /batata_stock_insufficient/i.test(msg);
}

async function refundOversoldStripeOrder(opts: {
  stripe: Stripe;
  supabase: ReturnType<typeof createClient>;
  orderId: string;
  sessionId?: string;
  paymentIntentId?: string;
}): Promise<{ refundId: string | null; already: boolean }> {
  const { stripe, supabase, orderId } = opts;
  const { data: order } = await supabase
    .from("orders")
    .select(
      "id, status, price_total, stripe_refund_id, stripe_payment_intent_id, stripe_checkout_session_id, stock_units_applied",
    )
    .eq("id", orderId)
    .maybeSingle();

  const existingRefund =
    (order?.stripe_refund_id as string | null)?.trim() ?? "";
  const orderPi =
    ((order?.stripe_payment_intent_id as string | null)?.trim() ?? "");
  let paymentIntentId =
    (opts.paymentIntentId ?? "").trim() ||
    orderPi;
  let sessionId =
    (opts.sessionId ?? "").trim() ||
    ((order?.stripe_checkout_session_id as string | null)?.trim() ?? "");

  if (!paymentIntentId && sessionId) {
    const session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ["payment_intent"],
    });
    paymentIntentId = await resolveCheckoutPaymentIntentId(stripe, session);
  }

  // RTBB-1115-P1: order já tem refund do PI A, mas settle/oversell aponta PI B órfão.
  if (
    existingRefund.length > 0 &&
    paymentIntentId.length > 0 &&
    orderPi.length > 0 &&
    paymentIntentId !== orderPi
  ) {
    return await refundOrphanDuplicatePaymentIntent({
      stripe,
      supabase,
      orderId,
      paymentIntentId,
      sessionId: sessionId || undefined,
      reason: "orphan_pi_after_order_refund",
    });
  }
  if (existingRefund.length > 0) {
    return { refundId: existingRefund, already: true };
  }

  let refundId: string | null = null;
  if (paymentIntentId) {
    const amountCents = euroToCents(Number(order?.price_total ?? 0));
    const refund = await stripe.refunds.create(
      {
        payment_intent: paymentIntentId,
        ...(amountCents > 0 ? { amount: amountCents } : {}),
        reason: "requested_by_customer",
        metadata: {
          fleaber_order_id: orderId,
          fleaber_reason: "oversell_stock_insufficient",
        },
      },
      { idempotencyKey: `fleaber_oversell_refund_${orderId}` },
    );
    refundId = refund.id;
  }

  // Nunca «pago»: cancela + marca refund. Sem stock_units_applied → restore não repõe.
  await supabase.from("orders").update({
    status: "cancelado",
    is_reservation: false,
    stripe_payment_intent_id: paymentIntentId || null,
    stripe_checkout_session_id: sessionId || null,
    stripe_refund_id: refundId,
    stripe_refunded_at: refundId ? new Date().toISOString() : null,
  }).eq("id", orderId);

  try {
    await logStripeCheckoutEvent(supabase, "sec_fase2_oversell_refund", {
      order_id: orderId,
      session_id: sessionId || null,
      payment_intent: paymentIntentId || null,
      refund_id: refundId,
    });
  } catch (_) {
    /* audit best-effort */
  }

  return { refundId, already: false };
}

/** Marca «pago» (trigger consome stock). Se stock insuficiente → refund idempotente. */
async function settleOrderPaidOrRefundOversell(opts: {
  supabase: ReturnType<typeof createClient>;
  stripe: Stripe;
  orderId: string;
  orderPatch: Record<string, unknown>;
  productId?: string;
  stripeIds?: { sessionId: string; paymentIntentId: string };
  /** Parcela desta order (bag). Se omitido → PI completo (single-order). */
  amountPaidCents?: number | null;
}): Promise<"paid" | "oversell_refunded" | "skipped"> {
  const {
    supabase,
    stripe,
    orderId,
    orderPatch,
    productId,
    stripeIds,
    amountPaidCents,
  } = opts;

  // PRE-F4: autoridade de refund — nunca copiar PI completo para cada linha do saco.
  if (
    amountPaidCents != null &&
    Number.isFinite(amountPaidCents) &&
    amountPaidCents > 0
  ) {
    orderPatch.amount_paid_cents = Math.round(amountPaidCents);
  } else if (stripeIds?.paymentIntentId) {
    try {
      const pi = await stripe.paymentIntents.retrieve(stripeIds.paymentIntentId);
      const paid = Number(pi.amount_received || pi.amount || 0);
      if (paid > 0) {
        orderPatch.amount_paid_cents = paid;
      }
    } catch (_) {
      /* best-effort */
    }
  }

  const { data: existing } = await supabase
    .from("orders")
    .select(
      "status, stripe_refund_id, stock_units_applied, seller_id, product_id, stripe_payment_intent_id, stripe_checkout_session_id",
    )
    .eq("id", orderId)
    .maybeSingle();
  const st = String(existing?.status ?? "").toLowerCase();
  if (isOrderLiquidatedStatus(st)) {
    // Sessions duplicadas: 2.ª captura Stripe após settle → reembolso do PI novo
    // (sem segunda venda / segundo mint). Retries unpaid continuam permitidos no create.
    const existingPi = String(existing?.stripe_payment_intent_id ?? "").trim();
    let newPi = (stripeIds?.paymentIntentId ?? "").trim();
    const newSid = (stripeIds?.sessionId ?? "").trim();
    if (!newPi && newSid) {
      try {
        const sess = await stripe.checkout.sessions.retrieve(newSid, {
          expand: ["payment_intent"],
        });
        newPi = await resolveCheckoutPaymentIntentId(stripe, sess);
      } catch (_) {
        /* best-effort */
      }
    }
    if (
      newPi.length > 0 &&
      existingPi.length > 0 &&
      newPi !== existingPi
    ) {
      await refundOrphanDuplicatePaymentIntent({
        stripe,
        supabase,
        orderId,
        paymentIntentId: newPi,
        sessionId: newSid || undefined,
        reason: "duplicate_checkout_session_after_paid",
      });
    } else if (newPi.length > 0 && existingPi.length === 0) {
      // RTBB-B-2012: já pago off-platform (sem PI) + captura Stripe tardia → refund.
      await refundOrphanDuplicatePaymentIntent({
        stripe,
        supabase,
        orderId,
        paymentIntentId: newPi,
        sessionId: newSid || undefined,
        reason: "stripe_after_offplatform_pago",
      });
    } else if (
      newSid.length > 0 &&
      newSid !== String(existing?.stripe_checkout_session_id ?? "").trim() &&
      newPi.length === 0
    ) {
      await logStripeCheckoutEvent(supabase, "sec_dup_session_pi_missing", {
        order_id: orderId,
        session_id: newSid,
        status: st,
      });
    }
    return "skipped";
  }
  if ((existing?.stripe_refund_id as string | null)?.trim()) {
    return "skipped";
  }

  const pid = (productId || String(existing?.product_id ?? "")).trim();
  if (pid) {
    const { data: beforeRow } = await supabase
      .from("products")
      .select("quantity, is_sold, list_on_marketplace, seller_id")
      .eq("id", pid)
      .maybeSingle();
    if (
      beforeRow &&
      existing?.seller_id &&
      String(beforeRow.seller_id) !== String(existing.seller_id)
    ) {
      throw new Error(
        `Checkout blocked: order seller does not own product (${orderId}).`,
      );
    }
    console.log(
      `BATATA_STOCK settle_before order=${orderId} product=${pid} qty=${beforeRow?.quantity ?? "?"}`,
    );
  }

  const { error: orderUpdateError } = await supabase
    .from("orders")
    .update(orderPatch)
    .eq("id", orderId);

  if (!orderUpdateError) {
    if (pid) {
      const { data: afterRow } = await supabase
        .from("products")
        .select("quantity, is_sold, list_on_marketplace")
        .eq("id", pid)
        .maybeSingle();
      console.log(
        `BATATA_STOCK settle_ok order=${orderId} product=${pid} ` +
          `qty_after=${afterRow?.quantity ?? "?"} is_sold=${afterRow?.is_sold ?? "?"}`,
      );
    }
    // ZIP 128: snapshot C2C/B2C no settle (idempotente; não bloqueia pagamento)
    try {
      await supabase.rpc("batata_stamp_order_commerce_channel", {
        p_order_id: orderId,
      });
    } catch (stampErr) {
      console.warn("batata_stamp_order_commerce_channel soft-fail", stampErr);
    }
    return "paid";
  }

  if (!isStockInsufficientError(orderUpdateError)) {
    throw orderUpdateError;
  }

  console.error(
    `BATATA_STOCK oversell order=${orderId} — refund Stripe`,
    orderUpdateError,
  );
  await refundOversoldStripeOrder({
    stripe,
    supabase,
    orderId,
    sessionId: stripeIds?.sessionId,
    paymentIntentId: stripeIds?.paymentIntentId,
  });
  return "oversell_refunded";
}

async function completeCommerceCheckoutAttempt(
  supabase: ReturnType<typeof createClient>,
  attemptId: string | null | undefined,
  stripeIds?: { sessionId?: string; paymentIntentId?: string },
) {
  const id = (attemptId ?? "").trim();
  if (!id) return;
  try {
    const { error } = await supabase.rpc("batata_commerce_checkout_complete", {
      p_attempt_id: id,
      p_stripe_checkout_session_id: stripeIds?.sessionId ?? null,
      p_stripe_payment_intent_id: stripeIds?.paymentIntentId ?? null,
    });
    if (error) {
      console.error("batata_commerce_checkout_complete", error);
    }
  } catch (e) {
    console.error("batata_commerce_checkout_complete_throw", e);
  }
}

async function settlePaidBagOrders(
  supabase: ReturnType<typeof createClient>,
  stripe: Stripe,
  lines: BagCheckoutLine[],
  buyerId: string,
  sellerId: string,
  liveIdMeta: string,
  stripeIds?: { sessionId: string; paymentIntentId: string },
  checkoutAttemptId?: string | null,
) {
  let piPaid = 0;
  if (stripeIds?.paymentIntentId) {
    try {
      const pi = await stripe.paymentIntents.retrieve(stripeIds.paymentIntentId);
      piPaid = Number(pi.amount_received || pi.amount || 0);
    } catch (_) {
      piPaid = 0;
    }
  }

  const orderIds = lines
    .map((l) => l.order_id?.trim() ?? "")
    .filter((id) => id.length > 0);
  const priceByOrder = new Map<string, number>();
  if (orderIds.length > 0) {
    const { data: rows } = await supabase
      .from("orders")
      .select("id, price_total")
      .in("id", orderIds);
    for (const r of rows ?? []) {
      priceByOrder.set(
        String(r.id),
        Math.max(0, Math.round(Number(r.price_total ?? 0) * 100)),
      );
    }
  }
  const sumPrices = [...priceByOrder.values()].reduce((a, b) => a + b, 0);
  let allocatedPaid = 0;
  let paidIndex = 0;
  const paidTargets = orderIds.length;

  for (const line of lines) {
    const orderId = line.order_id?.trim() ?? "";
    if (!orderId) continue;

    let productId = line.product_id?.trim() ?? "";
    if (!productId) {
      const { data: orderRow } = await supabase
        .from("orders")
        .select("product_id")
        .eq("id", orderId)
        .maybeSingle();
      productId = (orderRow?.product_id as string | undefined)?.trim() ?? "";
    }
    if (!productId) continue;

    const orderPatch: Record<string, unknown> = {
      status: "pago",
      is_reservation: false,
    };
    if (liveIdMeta.length > 0) orderPatch.live_id = liveIdMeta;
    const liveItemId = line.live_item_id?.trim() ?? "";
    if (liveItemId.length > 0) orderPatch.live_item_id = liveItemId;
    if (stripeIds?.sessionId) {
      orderPatch.stripe_checkout_session_id = stripeIds.sessionId;
    }
    if (stripeIds?.paymentIntentId) {
      orderPatch.stripe_payment_intent_id = stripeIds.paymentIntentId;
    }

    let linePaid: number | null = null;
    if (piPaid > 0 && paidTargets > 0) {
      const linePrice = priceByOrder.get(orderId) ?? 0;
      if (paidIndex === paidTargets - 1) {
        linePaid = Math.max(0, piPaid - allocatedPaid);
      } else if (sumPrices > 0) {
        linePaid = Math.round((piPaid * linePrice) / sumPrices);
        allocatedPaid += linePaid;
      } else {
        linePaid = Math.floor(piPaid / paidTargets);
        allocatedPaid += linePaid;
      }
      paidIndex += 1;
    }

    const settleResult = await settleOrderPaidOrRefundOversell({
      supabase,
      stripe,
      orderId,
      orderPatch,
      productId,
      stripeIds,
      amountPaidCents: linePaid,
    });
    if (settleResult !== "paid") {
      continue;
    }

    const requestId = line.reservation_request_id?.trim() ?? "";
    if (requestId.length > 0) {
      const { data: convertRes, error: convertErr } = await supabase.rpc(
        "batata_live_reservation_stripe_convert",
        { p_request_id: requestId, p_order_id: orderId },
      );
      if (convertErr) console.error("bag convert", convertErr);
      const ok =
        !convertErr &&
        convertRes &&
        typeof convertRes === "object" &&
        (convertRes as { ok?: boolean }).ok === true;
      if (!ok) {
        await supabase.rpc("batata_live_reconcile_stripe_order", {
          p_order_id: orderId,
          p_reservation_request_id: requestId,
        });
      }
    } else {
      await supabase.rpc("batata_live_reconcile_stripe_order", {
        p_order_id: orderId,
        p_reservation_request_id: null,
      });
    }
  }

  if (liveIdMeta.length > 0 && buyerId) {
    const firstItem = lines.find((l) => (l.live_item_id ?? "").trim().length > 0);
    const broadcastItemId = firstItem?.live_item_id?.trim() ?? "";
    if (broadcastItemId.length > 0) {
      try {
        await supabase.rpc("batata_live_purchase_broadcast", {
          p_live_id: liveIdMeta,
          p_buyer_id: buyerId,
          p_live_item_id: broadcastItemId,
        });
      } catch (broadcastError) {
        console.error("Fleaber live purchase broadcast failed", broadcastError);
      }
    }
  }

  // Phase 4: one fulfillment per checkout_attempt_id
  let attemptId = (checkoutAttemptId ?? "").trim();
  if (!attemptId && orderIds.length > 0) {
    const { data: attRow } = await supabase
      .from("orders")
      .select("checkout_attempt_id")
      .eq("id", orderIds[0])
      .maybeSingle();
    attemptId = String(attRow?.checkout_attempt_id ?? "").trim();
  }
  await completeCommerceCheckoutAttempt(supabase, attemptId, stripeIds);

  // ZIP149: marcar conjunto purchased após liquidação (idempotente)
  if (orderIds.length > 0) {
    const { data: bundleRows } = await supabase
      .from("orders")
      .select("bundle_id")
      .in("id", orderIds)
      .not("bundle_id", "is", null);
    const seen = new Set<string>();
    for (const r of bundleRows ?? []) {
      const bid = String(r.bundle_id ?? "").trim();
      if (!bid || seen.has(bid)) continue;
      seen.add(bid);
      const { error: markErr } = await supabase.rpc(
        "batata_bundle_mark_purchased",
        { p_bundle_id: bid },
      );
      if (markErr) console.error("batata_bundle_mark_purchased", markErr);
    }
  }
}

async function resolveStripeBagRequestId(
  supabase: ReturnType<typeof createClient>,
  options: {
    liveId: string;
    buyerId: string;
    itemIds: string[];
    orderId: string;
    reservationRequestId?: string;
  },
): Promise<string | null> {
  const reservationRequestId = options.reservationRequestId?.trim() ?? "";
  if (reservationRequestId.length > 0) {
    return reservationRequestId;
  }

  const orderTag = `stripe_checkout:${options.orderId}`;
  const { data: byOrder } = await supabase
    .from("live_reservation_requests")
    .select("id")
    .eq("live_id", options.liveId)
    .eq("buyer_id", options.buyerId)
    .eq("source", "fleaber_live")
    .in("status", ["pending", "accepted"])
    .in("live_item_id", options.itemIds)
    .ilike("notes", `%${orderTag}%`)
    .order("queue_position", { ascending: true })
    .limit(1);
  const linked = (byOrder?.[0]?.id as string | undefined)?.trim() ?? "";
  if (linked.length > 0) return linked;

  const { data: pick } = await supabase
    .from("live_reservation_requests")
    .select("id")
    .eq("live_id", options.liveId)
    .eq("buyer_id", options.buyerId)
    .eq("source", "fleaber_live")
    .in("status", ["pending", "accepted"])
    .in("live_item_id", options.itemIds)
    .order("queue_position", { ascending: true })
    .limit(1);
  return ((pick?.[0]?.id as string | undefined)?.trim() ?? "") || null;
}

function htmlResponse(
  title: string,
  message: string,
  options?: { appUrl?: string; status?: number; autoOpenApp?: boolean },
) {
  const appUrl = options?.appUrl ?? "fleaber://fleaber.com/";
  // Entidades HTML — evita mojibake se o gateway servir text/plain.
  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  const safeTitle = esc(title);
  const safeMessage = esc(message);
  const safeAppUrl = appUrl.replace(/"/g, "%22");
  const autoOpenScript = options?.autoOpenApp === true
    ? `<script>window.setTimeout(function(){ window.location.href = "${safeAppUrl}"; }, 250);</script>`
    : "";

  const html =
    `<!DOCTYPE html><html lang="pt"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fleaber</title>${autoOpenScript}</head>` +
    `<body style="margin:0;background:#F1F4F8;font-family:Arial,sans-serif;color:#101518;">` +
    `<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;box-sizing:border-box;">` +
    `<div style="width:100%;max-width:420px;background:#fff;border-radius:18px;padding:24px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.08);">` +
    `<h1 style="margin:0 0 10px;color:#007782;font-size:28px;">${safeTitle}</h1>` +
    `<p style="margin:0 0 18px;line-height:1.45;color:#57636C;">${safeMessage}</p>` +
    `<a href="${safeAppUrl}" style="display:block;background:#007782;color:white;text-decoration:none;padding:14px 16px;border-radius:12px;font-weight:700;">Voltar &agrave; app Fleaber</a>` +
    `<p style="margin:14px 0 0;color:#7A858C;font-size:12px;">Se a app n&atilde;o abrir, volta manualmente &agrave; Fleaber.</p>` +
    `</div></div></body></html>`;

  // Headers sem cors Content-Type; sem nosniff (se o gateway forçar text/plain, o browser ainda pode renderizar HTML).
  const headers = new Headers(corsHeaders);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.delete("X-Content-Type-Options");

  return new Response(html, {
    status: options?.status ?? 200,
    headers,
  });
}

function textResponse(message: string, status = 200) {
  return new Response(message, {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function isMobileUserAgent(ua: string): boolean {
  return /Android|iPhone|iPad|iPod/i.test(ua);
}

function intentRedirectResponse(appUrl: string) {
  return new Response(null, {
    status: 303,
    headers: {
      ...corsHeaders,
      "Location": appUrl,
      "Cache-Control": "no-store",
    },
  });
}

/** Após Stripe: telemóvel → Intent; Chrome desktop → HTML com deep link (Intent sozinho não abre). */
function stripePaidReturnResponse(
  req: Request,
  sessionId: string,
  returnOptions: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
  sessionMetadata?: Record<string, string> | null,
) {
  const webReturnOrigin = sanitizeWebReturnOrigin(
    sessionMetadata?.web_return_origin ?? "",
  );
  if (webReturnOrigin) {
    const webReturn =
      `${webReturnOrigin.replace(/\/$/, "")}/stripe-success?${stripeReturnQuery(sessionId, returnOptions).toString()}`;
    return new Response(null, {
      status: 303,
      headers: {
        ...corsHeaders,
        "Location": webReturn,
        "Cache-Control": "no-store",
      },
    });
  }

  const deep = fleaberDeepLinkUrl(sessionId, returnOptions);
  const ua = req.headers.get("user-agent") ?? "";
  if (isMobileUserAgent(ua)) {
    return intentRedirectResponse(androidIntentUrl(sessionId, returnOptions));
  }

  return htmlResponse(
    "Pagamento recebido",
    "O pagamento foi confirmado. Se a app não abrir sozinha, toca no botão abaixo.",
    { appUrl: deep, autoOpenApp: true },
  );
}

async function logStripeCheckoutEvent(
  supabase: ReturnType<typeof createClient>,
  event: string,
  detail: Record<string, unknown>,
) {
  try {
    await supabase.from("stripe_checkout_events").insert({
      session_id: (detail.session_id as string | undefined) ?? null,
      order_id: (detail.order_id as string | undefined) ?? null,
      product_id: (detail.product_id as string | undefined) ?? null,
      live_id: (detail.live_id as string | undefined) ?? null,
      buyer_id: (detail.buyer_id as string | undefined) ?? null,
      event,
      detail,
    });
  } catch (e) {
    console.error("stripe_checkout_events insert failed", e);
  }
}

function stripeReturnQuery(
  sessionId: string,
  options?: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const params = new URLSearchParams({ session_id: sessionId });
  if (options?.productId) {
    params.set("product_id", options.productId);
  }
  if (options?.orderId) {
    params.set("order_id", options.orderId);
  }
  if (options?.liveId) {
    params.set("liveId", options.liveId);
    params.set("live_id", options.liveId);
  }
  if (options?.playbackId) {
    params.set("playbackId", options.playbackId);
  }
  if (options?.isLive) {
    params.set("isLive", options.isLive);
  }
  if (options?.sellerId) {
    params.set("sellerId", options.sellerId);
  }
  return params;
}

function fleaberDeepLinkUrl(
  sessionId: string,
  options?: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const q = stripeReturnQuery(sessionId, options).toString();
  return `fleaber://fleaber.com/stripe-success?${q}`;
}

function androidIntentUrl(
  sessionId: string,
  options?: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const deepLinkPath = `fleaber.com/stripe-success?${stripeReturnQuery(sessionId, options).toString()}`;
  const fallback = encodeURIComponent("https://fleaber.app");
  return `intent://${deepLinkPath}#Intent;scheme=fleaber;package=pt.fleaber.app;S.browser_fallback_url=${fallback};end`;
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    // ZIP 172: default TEST via resolveStripeSecretForMode — sem fallback LIVE.
    const resolvedTest = resolveStripeSecretForMode("test");
    if (!resolvedTest.ok || !resolvedTest.key) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: resolvedTest.error ?? "stripe_test_unavailable",
          message: "Checkout TEST indisponível (credencial TEST em falta).",
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const stripeSecretKey = resolvedTest.key;
    if (!supabaseUrl) {
      throw new Error("SUPABASE_URL is not configured.");
    }

    let stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });
    let activeStripeMode: "test" | "live" = "test";

    // FASE2 E2E (staging/sk_test_ only): settle por PaymentIntent já pago.
    // Autorização: Bearer TEM de ser o secret service_role (timing-safe).
    // NÃO confiar em JWT forjado (alg=none / payload role).
    if (
      req.method === "POST" &&
      new URL(req.url).searchParams.get("fase2_e2e_settle") === "1"
    ) {
      const e2eGate = assertDestructiveHarnessAllowed();
      if (!e2eGate.ok) {
        return new Response(
          JSON.stringify({ ok: false, error: e2eGate.error }),
          {
            status: e2eGate.status,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      if (!serviceRoleKey) {
        throw new Error("Supabase service role is not configured.");
      }
      const authHdr = req.headers.get("Authorization") ?? "";
      const tok = authHdr.replace(/^Bearer\s+/i, "").trim();
      const a = new TextEncoder().encode(tok);
      const b = new TextEncoder().encode(serviceRoleKey);
      let same = a.length === b.length;
      if (same) {
        let diff = 0;
        for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
        same = diff === 0;
      }
      if (!same) {
        return new Response(
          JSON.stringify({ ok: false, error: "service_role required" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const e2eBody = await req.json() as {
        order_id?: string;
        payment_intent_id?: string;
        product_id?: string;
        session_id?: string;
        bag_checkout?: boolean;
        bag_lines?: BagCheckoutLine[];
        buyer_id?: string;
        seller_id?: string;
      };
      const orderId = (e2eBody.order_id ?? "").trim();
      const paymentIntentId = (e2eBody.payment_intent_id ?? "").trim();
      const productId = (e2eBody.product_id ?? "").trim();
      const sessionIdE2e = (e2eBody.session_id ?? "").trim();
      const bagLines = Array.isArray(e2eBody.bag_lines)
        ? e2eBody.bag_lines
        : [];
      const isBagSettle =
        e2eBody.bag_checkout === true && bagLines.length > 0;

      if (!paymentIntentId || (!isBagSettle && !orderId)) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: isBagSettle
              ? "payment_intent_id + bag_lines"
              : "order_id e payment_intent_id",
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
      if (pi.status !== "succeeded") {
        return new Response(
          JSON.stringify({
            ok: false,
            error: `PI status=${pi.status} (esperado succeeded)`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const supabase = createClient(supabaseUrl, serviceRoleKey);

      // --- Bag multi-line: NÃO copiar PI completo para cada order ---
      if (isBagSettle) {
        const buyerId = (e2eBody.buyer_id ?? "").trim();
        const sellerId = (e2eBody.seller_id ?? "").trim();
        if (!buyerId || !sellerId) {
          return new Response(
            JSON.stringify({ ok: false, error: "buyer_id e seller_id (bag)" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
        await settlePaidBagOrders(
          supabase,
          stripe,
          bagLines,
          buyerId,
          sellerId,
          "",
          { sessionId: sessionIdE2e, paymentIntentId },
        );
        const orderIds = bagLines
          .map((l) => (l.order_id ?? "").trim())
          .filter((id) => id.length > 0);
        const { data: ordersAfter } = await supabase
          .from("orders")
          .select(
            "id, status, price_total, amount_paid_cents, stock_units_applied, stripe_payment_intent_id, product_id",
          )
          .in("id", orderIds);
        const sumPaid = (ordersAfter ?? []).reduce(
          (s, o) => s + Number(o.amount_paid_cents ?? 0),
          0,
        );
        const piAmt = Number(pi.amount_received || pi.amount || 0);
        return new Response(
          JSON.stringify({
            ok: true,
            bag: true,
            settleResult: "bag",
            payment_intent: {
              id: pi.id,
              status: pi.status,
              amount: pi.amount,
              amount_received: pi.amount_received,
              currency: pi.currency,
            },
            orders: ordersAfter,
            sum_amount_paid_cents: sumPaid,
            pi_amount_cents: piAmt,
            invariant_sum_eq_pi: sumPaid === piAmt,
            invariant_no_line_has_full_pi: (ordersAfter ?? []).every(
              (o) =>
                Number(o.amount_paid_cents ?? 0) < piAmt ||
                (ordersAfter ?? []).length <= 1,
            ),
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // RTBB-1115: se já liquidada, NÃO sobrescrever PI A com PI B — só orphan refund.
      const { data: beforeSettle } = await supabase
        .from("orders")
        .select("status, stripe_payment_intent_id")
        .eq("id", orderId)
        .maybeSingle();
      if (isOrderLiquidatedStatus(beforeSettle?.status)) {
        const settleResult = await settleOrderPaidOrRefundOversell({
          supabase,
          stripe,
          orderId,
          orderPatch: {
            status: "pago",
            is_reservation: false,
          },
          productId: productId || undefined,
          stripeIds: {
            sessionId: sessionIdE2e,
            paymentIntentId,
          },
        });
        const { data: orderRowLiq } = await supabase.from("orders").select(
          "id, status, stock_units_applied, stripe_refund_id, stripe_payment_intent_id, price_total, amount_paid_cents",
        ).eq("id", orderId).maybeSingle();
        return new Response(
          JSON.stringify({
            ok: true,
            settleResult,
            already_liquidated: true,
            order: orderRowLiq,
            payment_intent: {
              id: pi.id,
              status: pi.status,
              amount: pi.amount,
              amount_received: pi.amount_received,
              currency: pi.currency,
            },
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      await supabase.from("orders").update({
        stripe_payment_intent_id: paymentIntentId,
        price_total: (pi.amount_received || pi.amount) / 100,
        amount_paid_cents: Number(pi.amount_received || pi.amount || 0) || null,
      }).eq("id", orderId);

      const settleResult = await settleOrderPaidOrRefundOversell({
        supabase,
        stripe,
        orderId,
        orderPatch: {
          status: "pago",
          is_reservation: false,
          stripe_payment_intent_id: paymentIntentId,
        },
        productId: productId || undefined,
        stripeIds: { sessionId: sessionIdE2e, paymentIntentId },
      });

      const { data: orderRow } = await supabase.from("orders").select(
        "id, status, stock_units_applied, stripe_refund_id, stripe_payment_intent_id, price_total, amount_paid_cents",
      ).eq("id", orderId).maybeSingle();

      return new Response(
        JSON.stringify({
          ok: true,
          settleResult,
          order: orderRow,
          payment_intent: {
            id: pi.id,
            status: pi.status,
            amount: pi.amount,
            amount_received: pi.amount_received,
            currency: pi.currency,
          },
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (req.method === "GET") {
      const url = new URL(req.url);
      const sessionId = url.searchParams.get("session_id");
      const deepLinkUrl =
        sessionId != null
          ? `fleaber://fleaber.com/stripe-success?session_id=${encodeURIComponent(sessionId)}`
          : "fleaber://fleaber.com/";
      const appUrl = sessionId != null ? androidIntentUrl(sessionId) : deepLinkUrl;
      if (!sessionId) {
        return textResponse("Sessão Stripe em falta.", 400);
      }

      // SEC-018b / FASE3: rate-limit settle. 429 NÃO significa pago.
      // Se a order já está paga, responder sucesso (idempotente) sem contar como fail-open.
      if (serviceRoleKey) {
        const supabaseRate = createClient(supabaseUrl, serviceRoleKey);
        const settleRate = await checkAnonRate(
          supabaseRate,
          `checkout_settle:${sessionId.slice(0, 64)}`,
          "create-payment-intent-get",
          30,
        );
        if (settleRate.rateLimited) {
          let oidEarly: string | undefined;
          try {
            oidEarly = (
              await stripe.checkout.sessions.retrieve(sessionId)
            ).metadata?.order_id;
          } catch (_) {
            return textResponse(
              "Demasiados pedidos. Volta à app Fleaber e espera um momento.",
              429,
            );
          }
          if (oidEarly) {
            const { data: ordEarly } = await supabaseRate
              .from("orders")
              .select("status")
              .eq("id", oidEarly)
              .maybeSingle();
            const st = String(ordEarly?.status ?? "").toLowerCase();
            if (
              st === "pago" ||
              st === "enviado" ||
              st === "entregue" ||
              st === "concluido"
            ) {
              // já liquidado — UX OK
            } else {
              return textResponse(
                "Demasiados pedidos. Volta à app Fleaber e espera um momento.",
                429,
              );
            }
          } else {
            return textResponse(
              "Demasiados pedidos. Volta à app Fleaber e espera um momento.",
              429,
            );
          }
        }
      }

      let session: Stripe.Checkout.Session;
      try {
        session = await stripe.checkout.sessions.retrieve(sessionId, {
          expand: ["payment_intent"],
        });
      } catch (_) {
        // P3 Indep: não ecoar «No such checkout.session» (oráculo Stripe).
        return textResponse(
          "Pagamento ainda não confirmado. Se já pagaste, aguarda alguns segundos e volta à app Fleaber.",
          400,
        );
      }
      const productId = session.metadata?.product_id;
      const orderId = session.metadata?.order_id;
      const liveId = session.metadata?.live_id;
      const playbackId = session.metadata?.playback_id;
      const isLive = session.metadata?.is_live;
      const liveSellerId = session.metadata?.live_seller_id;
      const returnOptions = {
        productId,
        orderId,
        liveId,
        playbackId,
        isLive,
        sellerId: liveSellerId,
      };
      const successfulAppUrl = fleaberDeepLinkUrl(sessionId, returnOptions);
      let updateError = "";
      if (
        url.searchParams.get("checkout_return") === "success" &&
        session.payment_status === "paid"
      ) {
        try {
          if (!serviceRoleKey) {
            throw new Error("Supabase service role is not configured.");
          }
          const supabase = createClient(supabaseUrl, serviceRoleKey);
          const buyerId = session.metadata?.buyer_id;
          const sellerId = session.metadata?.seller_id;
          const total = Number(session.metadata?.total ?? 0);

          const liveIdMeta = session.metadata?.live_id?.trim() ?? "";
          const bagLines = parseBagCheckoutLines(session.metadata);
          const isBagPaid =
            session.metadata?.bag_checkout === "true" && bagLines.length > 0;

          // ZIP 149.1: replay idempotente — se já liquidado para esta session, sucesso sem re-quote.
          {
            const candidateIds: string[] = [];
            if (isBagPaid) {
              for (const l of bagLines) {
                const oid = (l.order_id ?? "").trim();
                if (oid) candidateIds.push(oid);
              }
            } else if ((orderId ?? "").trim()) {
              candidateIds.push((orderId ?? "").trim());
            }
            if (candidateIds.length > 0) {
              const { data: paidRows } = await supabase
                .from("orders")
                .select("id, status, stripe_checkout_session_id")
                .in("id", candidateIds);
              const rows = paidRows ?? [];
              const allLiquidated =
                rows.length === candidateIds.length &&
                rows.every((r) =>
                  isOrderLiquidatedStatus(String(r.status ?? ""))
                );
              const sameSession = rows.every((r) => {
                const sid = String(r.stripe_checkout_session_id ?? "").trim();
                return sid.length === 0 || sid === sessionId;
              });
              if (allLiquidated && sameSession) {
                await logStripeCheckoutEvent(
                  supabase,
                  "sec_settle_idempotent_already_paid",
                  {
                    session_id: sessionId,
                    order_ids: candidateIds,
                    bag: isBagPaid,
                  },
                );
                // Skip restante settle — resposta de sucesso abaixo.
                updateError = "";
                // Jump out of try by not throwing; mark via flag on session meta path
                (session as unknown as { __fleaber_already_settled?: boolean })
                  .__fleaber_already_settled = true;
              }
            }
          }

          if (
            !(session as unknown as { __fleaber_already_settled?: boolean })
              .__fleaber_already_settled
          ) {
          // FASE1: montante Stripe pago deve coincidir com total servidor (metadata).
          const serverAmountMeta = Number(
            session.metadata?.server_amount_cents ??
              session.metadata?.total ??
              NaN,
          );
          const paidTotal = Number(session.amount_total ?? NaN);
          if (
            Number.isFinite(serverAmountMeta) &&
            serverAmountMeta >= 50 &&
            Number.isFinite(paidTotal) &&
            paidTotal !== serverAmountMeta
          ) {
            await logStripeCheckoutEvent(supabase, "sec_fase1_settle_amount_mismatch", {
              session_id: sessionId,
              order_id: orderId ?? null,
              server_amount_cents: serverAmountMeta,
              stripe_amount_total: paidTotal,
            });
            throw new Error(
              "Pagamento com montante inválido. Contacta o suporte Fleaber.",
            );
          }
          const stripeIds = stripeIdsFromSession(session);
          if (!stripeIds.paymentIntentId) {
            stripeIds.paymentIntentId = await resolveCheckoutPaymentIntentId(
              stripe,
              session,
            );
          }

          // P0-01 defesa em profundidade: recomputar quote a partir das ORDERs.
          if (buyerId && Number.isFinite(paidTotal) && paidTotal >= 50) {
            try {
              const settleBody: PaymentIntentRequest = {
                order_id: orderId ?? bagLines[0]?.order_id,
                buyer_id: buyerId,
                shipping_method: session.metadata?.shipping_method,
                prize_shipping: session.metadata?.prize_shipping === "1",
                checkout_attempt_id: session.metadata?.checkout_attempt_id,
                bag_checkout: isBagPaid,
                bag_lines: isBagPaid
                  ? bagLines.map((l) => ({ order_id: l.order_id }))
                  : undefined,
              };
              const recomputed = await resolveServerCheckoutQuote(
                supabase,
                settleBody,
                isBagPaid,
                isBagPaid
                  ? bagLines.map((l) => ({ order_id: l.order_id }))
                  : [],
                buyerId,
                { forSettle: true },
              );
              if (recomputed.amountCents !== paidTotal) {
                await logStripeCheckoutEvent(
                  supabase,
                  "sec_p001_settle_order_quote_mismatch",
                  {
                    session_id: sessionId,
                    order_id: orderId ?? null,
                    paid_total: paidTotal,
                    order_quote_cents: recomputed.amountCents,
                  },
                );
                throw new Error(
                  "Pagamento inconsistente com a encomenda (montante). Contacta o suporte Fleaber.",
                );
              }
            } catch (reErr) {
              const msg = reErr instanceof Error ? reErr.message : String(reErr);
              // ZIP 144.3: mismatch/portes NÃO são «Artigo esgotado».
              if (
                msg.includes("inconsistente") ||
                msg.includes("inválido") ||
                msg.includes("montante") ||
                msg.includes("Portes") ||
                msg.includes("portes") ||
                msg.includes("attempt")
              ) {
                throw reErr;
              }
              // S2-P0-01: se a order JÁ está liquidada, quote fail ≠ oversell.
              // Replay GET/webhook não deve emitir refund nem cancelar a venda.
              const oid = (orderId ?? bagLines[0]?.order_id ?? "").trim();
              let alreadyLiquidated = false;
              if (oid.length > 0) {
                const { data: paidRow } = await supabase
                  .from("orders")
                  .select(
                    "status, stripe_refund_id, stripe_checkout_session_id, stripe_payment_intent_id, amount_paid_cents",
                  )
                  .eq("id", oid)
                  .maybeSingle();
                const stPay = String(paidRow?.status ?? "").toLowerCase();
                const refunded = String(paidRow?.stripe_refund_id ?? "").trim();
                const keptPi = String(paidRow?.stripe_payment_intent_id ?? "")
                  .trim();
                const keptSid = String(
                  paidRow?.stripe_checkout_session_id ?? "",
                ).trim();
                if (
                  refunded.length === 0 &&
                  isOrderLiquidatedStatus(stPay)
                ) {
                  alreadyLiquidated = true;
                  await logStripeCheckoutEvent(
                    supabase,
                    "sec_settle_replay_already_pago",
                    {
                      session_id: sessionId,
                      order_id: oid,
                      status: stPay,
                      quote_error: msg,
                    },
                  );
                  // RTBB-1115-P1: Session B ≠ Session A → refund órfão já no quote-fail.
                  const orphanPi = (stripeIds.paymentIntentId || "").trim();
                  if (
                    orphanPi.length > 0 &&
                    keptPi.length > 0 &&
                    orphanPi !== keptPi
                  ) {
                    await refundOrphanDuplicatePaymentIntent({
                      stripe,
                      supabase,
                      orderId: oid,
                      paymentIntentId: orphanPi,
                      sessionId: sessionId || undefined,
                      reason: "duplicate_session_quote_fail_path",
                    });
                  } else if (
                    sessionId &&
                    keptSid.length > 0 &&
                    sessionId !== keptSid &&
                    orphanPi.length > 0 &&
                    keptPi.length === 0
                  ) {
                    await refundOrphanDuplicatePaymentIntent({
                      stripe,
                      supabase,
                      orderId: oid,
                      paymentIntentId: orphanPi,
                      sessionId,
                      reason: "stripe_after_offplatform_pago",
                    });
                  }
                } else if (
                  // Order cancelada/refunded no PI A; Session B ainda paga.
                  (refunded.length > 0 ||
                    stPay === "cancelado" ||
                    stPay === "cancelled") &&
                  (stripeIds.paymentIntentId || "").trim().length > 0 &&
                  (stripeIds.paymentIntentId || "").trim() !== keptPi
                ) {
                  await refundOversoldStripeOrder({
                    stripe,
                    supabase,
                    orderId: oid,
                    sessionId: sessionId || undefined,
                    paymentIntentId: stripeIds.paymentIntentId || undefined,
                  });
                  throw new Error(
                    "Artigo esgotado. O pagamento será reembolsado automaticamente.",
                  );
                }
              }
              if (alreadyLiquidated) {
                // Continuar para settleOrderPaidOrRefundOversell → skipped.
              } else if (oid.length > 0) {
                // F-RTF-P1-001: sessão paga mas quote/settle impossível → refund oversell
                try {
                  await refundOversoldStripeOrder({
                    stripe,
                    supabase,
                    orderId: oid,
                    sessionId: sessionId || undefined,
                    paymentIntentId: stripeIds.paymentIntentId || undefined,
                  });
                  await logStripeCheckoutEvent(
                    supabase,
                    "sec_fase2_oversell_refund_quote_fail",
                    {
                      session_id: sessionId,
                      order_id: oid,
                      error: msg,
                    },
                  );
                  throw new Error(
                    "Artigo esgotado. O pagamento será reembolsado automaticamente.",
                  );
                } catch (refundPathErr) {
                  const rmsg = refundPathErr instanceof Error
                    ? refundPathErr.message
                    : String(refundPathErr);
                  if (rmsg.includes("reembolsado")) throw refundPathErr;
                  await logStripeCheckoutEvent(
                    supabase,
                    "sec_p001_settle_order_quote_failed",
                    {
                      session_id: sessionId,
                      order_id: orderId ?? null,
                      error: msg,
                      refund_error: rmsg,
                    },
                  );
                  throw new Error(
                    "Não foi possível validar o pagamento. Contacta o suporte Fleaber.",
                  );
                }
              } else {
                await logStripeCheckoutEvent(
                  supabase,
                  "sec_p001_settle_order_quote_failed",
                  {
                    session_id: sessionId,
                    order_id: orderId ?? null,
                    error: msg,
                  },
                );
                throw new Error(
                  "Não foi possível validar o pagamento. Contacta o suporte Fleaber.",
                );
              }
            }
          }

          if (isBagPaid && buyerId && sellerId) {
            await settlePaidBagOrders(
              supabase,
              stripe,
              bagLines,
              buyerId,
              sellerId,
              liveIdMeta,
              stripeIds,
              session.metadata?.checkout_attempt_id ?? null,
            );
            if (liveIdMeta.length === 0) {
              await sendMarketplaceBagPaidChatMessage(
                supabase,
                buyerId,
                sellerId,
                bagLines,
                Number(session.metadata?.total ?? 0),
              );
            }
          } else if (orderId && productId && buyerId && sellerId) {
            const orderPatch: Record<string, unknown> = {
              status: "pago",
              is_reservation: false,
            };
            const liveItemIdMeta = session.metadata?.live_item_id?.trim() ?? "";
            if (liveIdMeta.length > 0) orderPatch.live_id = liveIdMeta;
            if (liveItemIdMeta.length > 0) {
              orderPatch.live_item_id = liveItemIdMeta;
            }
            if (stripeIds.sessionId) {
              orderPatch.stripe_checkout_session_id = stripeIds.sessionId;
            }
            if (stripeIds.paymentIntentId) {
              orderPatch.stripe_payment_intent_id = stripeIds.paymentIntentId;
            }

            // FASE2: trigger consome stock; se esgotado → refund Stripe (não «pago»).
            const settleResult = await settleOrderPaidOrRefundOversell({
              supabase,
              stripe,
              orderId,
              orderPatch,
              productId,
              stripeIds,
            });
            if (settleResult === "oversell_refunded") {
              throw new Error(
                "Artigo esgotado. O pagamento será reembolsado automaticamente.",
              );
            }

            try {
              // CHAT-MULTI v5: 1 encomenda → 1 chat dedicado.
              // Preferir paid_chat_id criado no POST checkout; nunca reutilizar
              // thread de compras anteriores do mesmo artigo.
              const metaChatId =
                (session.metadata?.paid_chat_id ?? "").trim();

              const { data: existingMessage } = await supabase
                .from("chat_messages")
                .select("id, chat_id, text")
                .like("text", `%${orderId}%`)
                .limit(20);

              const paidRow = (existingMessage ?? []).find((row) => {
                const t = (row as { text?: string }).text ?? "";
                return (
                  t.includes('"kind":"seguro_fleaber_paid"') &&
                  t.includes(`"order_id":"${orderId}"`)
                );
              }) as { chat_id?: string } | undefined;

              let chatId = (paidRow?.chat_id ?? "").trim();
              let createdNew = false;

              if (!chatId && metaChatId) {
                chatId = metaChatId;
              }

              if (!chatId) {
                const { data: newChat, error: chatInsErr } = await supabase
                  .from("chats")
                  .insert({
                    user_a: buyerId,
                    user_b: sellerId,
                    product_id: productId,
                  })
                  .select("id")
                  .single();
                if (chatInsErr) {
                  console.error("CHAT_MULTI chat insert failed", chatInsErr);
                }
                chatId = (newChat?.id ?? "").trim();
                createdNew = chatId.length > 0;
              }

              await logStripeCheckoutEvent(supabase, "chat_multi_edge_v5", {
                order_id: orderId,
                product_id: productId,
                buyer_id: buyerId,
                chat_id: chatId || null,
                meta_paid_chat_id: metaChatId || null,
                reused_existing_msg: Boolean(paidRow),
                created_new_chat: createdNew,
                session_id: stripeIds.sessionId ?? session.id,
              });

              if (chatId) {
                const text = `FLEABER_JSON_V1:${JSON.stringify({
                  kind: "seguro_fleaber_paid",
                  order_id: orderId,
                  total: Number.isFinite(total) ? total / 100 : null,
                  v: 1,
                })}`;

                if (!paidRow) {
                  const { error: msgErr } = await supabase
                    .from("chat_messages")
                    .insert({
                      sender_id: buyerId,
                      receiver_id: sellerId,
                      chat_id: chatId,
                      text,
                      is_read: false,
                      is_reservation: true,
                    });
                  if (msgErr) {
                    console.error("CHAT_MULTI message insert failed", msgErr);
                  }
                }

                await supabase
                  .from("chats")
                  .update({
                    last_message: "Compra paga pelo Seguro Fleaber",
                    last_message_time: new Date().toISOString(),
                  })
                  .eq("id", chatId);
              }
            } catch (chatError) {
              console.error("Fleaber chat update failed", chatError);
            }

            // Saco da live: marcar reservas leves como convertidas após pagamento.
            if (liveIdMeta.length > 0 && buyerId) {
              try {
                const itemIds = new Set<string>();
                if (liveItemIdMeta.length > 0) {
                  itemIds.add(liveItemIdMeta);
                }
                if (productId) {
                  const { data: productRow } = await supabase
                    .from("products")
                    .select("ref_code")
                    .eq("id", productId)
                    .maybeSingle();
                  const refCode = (productRow?.ref_code as string | undefined)?.trim() ?? "";
                  if (refCode.length > 0) {
                    const { data: liveItems } = await supabase
                      .from("live_items")
                      .select("id")
                      .eq("live_id", liveIdMeta)
                      .eq("ref_code", refCode);
                    for (const row of liveItems ?? []) {
                      const id = (row.id as string | undefined)?.trim() ?? "";
                      if (id.length > 0) itemIds.add(id);
                    }
                  }
                }
                const ids = [...itemIds];
                if (ids.length > 0) {
                  const reservationRequestIdMeta =
                    session.metadata?.reservation_request_id?.trim() ?? "";
                  const requestId = await resolveStripeBagRequestId(supabase, {
                    liveId: liveIdMeta,
                    buyerId,
                    itemIds: ids,
                    orderId: orderId ?? "",
                    reservationRequestId: reservationRequestIdMeta,
                  });

                  let convertedItemId = liveItemIdMeta;
                  if (requestId) {
                    const { data: convertRes, error: convertErr } =
                      await supabase.rpc("batata_live_reservation_stripe_convert", {
                        p_request_id: requestId,
                        p_order_id: orderId,
                      });
                    if (convertErr) {
                      console.error("stripe convert rpc", convertErr);
                    }
                    const ok =
                      !convertErr &&
                      convertRes &&
                      typeof convertRes === "object" &&
                      (convertRes as { ok?: boolean }).ok === true;
                    if (!ok) {
                      const { error: reconcileErr } = await supabase.rpc(
                        "batata_live_reconcile_stripe_order",
                        {
                          p_order_id: orderId,
                          p_reservation_request_id: requestId,
                        },
                      );
                      if (reconcileErr) {
                        console.error("stripe reconcile fallback", reconcileErr);
                      }
                    }
                    const fromRpc = (convertRes as { live_item_id?: string } | null)
                      ?.live_item_id;
                    if (typeof fromRpc === "string" && fromRpc.trim().length > 0) {
                      convertedItemId = fromRpc.trim();
                    }
                  } else {
                    // Compra directa (sem reserva prévia): registo converted no saco.
                    for (const itemId of ids) {
                      const { data: convertedRows } = await supabase
                        .from("live_reservation_requests")
                        .select("id")
                        .eq("live_id", liveIdMeta)
                        .eq("buyer_id", buyerId)
                        .eq("live_item_id", itemId)
                        .eq("status", "converted")
                        .limit(1);
                      if (!convertedRows || convertedRows.length === 0) {
                        await supabase.from("live_reservation_requests").insert({
                          live_id: liveIdMeta,
                          live_item_id: itemId,
                          seller_id: sellerId,
                          buyer_id: buyerId,
                          requested_qty: 1,
                          source: "fleaber_live",
                          status: "converted",
                          notes: "stripe_paid_direct",
                        });
                      }
                      const { data: stock } = await supabase.rpc(
                        "batata_live_item_stock",
                        { p_live_item_id: itemId },
                      );
                      const avail =
                        stock && typeof stock === "object"
                          ? Number((stock as { available_qty?: number }).available_qty ?? 1)
                          : 1;
                      if (avail <= 0) {
                        await supabase
                          .from("live_items")
                          .update({ status: "sold" })
                          .eq("id", itemId);
                      }
                      try {
                        await supabase.rpc("batata_maybe_fomo_last_unit", {
                          p_live_item_id: itemId,
                        });
                      } catch (fomoError) {
                        console.error(
                          "Fleaber live FOMO last unit failed",
                          fomoError,
                        );
                      }
                    }
                  }

                  const broadcastItemId = convertedItemId.length > 0
                    ? convertedItemId
                    : ids[0];
                  if (broadcastItemId.length > 0) {
                    try {
                      await supabase.rpc("batata_live_purchase_broadcast", {
                        p_live_id: liveIdMeta,
                        p_buyer_id: buyerId,
                        p_live_item_id: broadcastItemId,
                      });
                    } catch (broadcastError) {
                      console.error(
                        "Fleaber live purchase broadcast failed",
                        broadcastError,
                      );
                    }
                  }

                  console.log(
                    JSON.stringify({
                      event: "stripe.live_bag_converted",
                      live_id: liveIdMeta,
                      live_item_ids: ids,
                      reservation_request_id: requestId,
                      order_id: orderId,
                    }),
                  );
                }
              } catch (bagError) {
                console.error("Fleaber live bag convert failed", bagError);
              }
            }
          } else {
            throw new Error("Missing checkout metadata.");
          }
          } // ZIP 149.1: fim bloco !already_settled
        } catch (error) {
          updateError = error instanceof Error ? error.message : String(error);
          // ZIP 149.1: se já liquidado, nunca 500 por re-quote no replay
          try {
            if (serviceRoleKey && session.payment_status === "paid") {
              const sb = createClient(supabaseUrl, serviceRoleKey);
              const bagReplay = parseBagCheckoutLines(session.metadata);
              const idsReplay: string[] = [];
              if (
                session.metadata?.bag_checkout === "true" && bagReplay.length > 0
              ) {
                for (const l of bagReplay) {
                  const oid = (l.order_id ?? "").trim();
                  if (oid) idsReplay.push(oid);
                }
              } else if ((orderId ?? "").trim()) {
                idsReplay.push((orderId ?? "").trim());
              }
              if (idsReplay.length > 0) {
                const { data: rowsR } = await sb
                  .from("orders")
                  .select("id, status")
                  .in("id", idsReplay);
                if (
                  (rowsR ?? []).length === idsReplay.length &&
                  (rowsR ?? []).every((r) =>
                    isOrderLiquidatedStatus(String(r.status ?? ""))
                  )
                ) {
                  await logStripeCheckoutEvent(
                    sb,
                    "sec_settle_replay_soft_ok",
                    {
                      session_id: sessionId,
                      order_ids: idsReplay,
                      prior_error: updateError,
                    },
                  );
                  updateError = "";
                }
              }
            }
          } catch (_) { /* keep updateError */ }
        }
      }

      if (url.searchParams.get("checkout_return") === "cancel") {
        console.log(
          JSON.stringify({
            event: "stripe.checkout.cancel",
            session_id: sessionId,
            order_id: orderId,
            live_id: liveId,
          }),
        );
      }

      const paid = session.payment_status === "paid";
      if (serviceRoleKey) {
        const supabaseLog = createClient(supabaseUrl, serviceRoleKey);
        await logStripeCheckoutEvent(supabaseLog, paid ? "checkout.paid" : "checkout.pending", {
          session_id: sessionId,
          order_id: orderId,
          product_id: productId,
          live_id: liveId,
          buyer_id: session.metadata?.buyer_id,
          payment_status: session.payment_status,
          checkout_return: url.searchParams.get("checkout_return"),
          update_error: updateError || null,
          deep_link: successfulAppUrl,
        });
      }
      if (paid && updateError.length === 0) {
        return stripePaidReturnResponse(
          req,
          sessionId,
          returnOptions,
          session.metadata as Record<string, string> | null,
        );
      }
      if (paid && updateError.length > 0) {
        // Fail-closed: Stripe cobrou mas settle falhou → 5xx para webhook retry.
        return textResponse(
          `PAGAMENTO RECEBIDO\n\nErro ao atualizar a encomenda:\n${updateError}\n\nVolta à app Fleaber. Se o artigo não ficar vendido, envia este texto.`,
          500,
        );
      }
      return textResponse(
        "Pagamento ainda não confirmado. Se já pagaste, aguarda alguns segundos e volta à app Fleaber.",
        402,
      );
    }

    const body = (await req.json()) as PaymentIntentRequest;
    const requestedCurrency = String(body.currency ?? "eur").trim().toLowerCase();
    if (requestedCurrency !== "eur") {
      throw new Error("Checkout blocked: only EUR is supported.");
    }
    const currency = "eur";
    // B-BAG-DUP / BF-P2: mesmo order_id 2× (hífen∥compact) → uma linha.
    const rawBag = Array.isArray(body.bag_lines) ? body.bag_lines : [];
    const seenBag = new Set<string>();
    const bagLines: BagCheckoutLine[] = [];
    for (const line of rawBag) {
      const oid = String(line?.order_id ?? "").trim();
      if (!oid) continue;
      const oidKey = hydrateCompactUuid(oid).replace(/-/g, "").toLowerCase();
      if (!oidKey || seenBag.has(oidKey)) continue;
      seenBag.add(oidKey);
      bagLines.push(line);
    }
    const isBagCheckout = body.bag_checkout === true && bagLines.length > 0;

    // ZIP 172: sticky ops_stripe_mode — LIVE só com STRIPE_SECRET_KEY_LIVE + GO.
    if (serviceRoleKey) {
      const supabaseMode = createClient(supabaseUrl, serviceRoleKey);
      const peekIds = [
        ...(body.order_id ? [String(body.order_id).trim()] : []),
        ...bagLines.map((l) => String(l.order_id ?? "").trim()),
      ].filter(Boolean);
      if (peekIds.length > 0) {
        const { data: modeRows } = await supabaseMode
          .from("orders")
          .select("id, ops_stripe_mode, seller_id, buyer_id, amount_paid_cents, price_total")
          .in("id", peekIds);
        const modes = new Set(
          (modeRows ?? []).map((r) =>
            normalizeStripeMode((r as { ops_stripe_mode?: string }).ops_stripe_mode)
          ),
        );
        if (modes.has("live") && modes.has("test")) {
          return new Response(
            JSON.stringify({
              ok: false,
              error: "mixed_stripe_modes_in_bag",
              message:
                "Saco mistura encomendas TEST e LIVE — separa os checkouts.",
            }),
            {
              status: 409,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
        if (modes.has("live")) {
          const live = resolveStripeSecretForMode("live");
          if (!live.ok || !live.key) {
            return new Response(
              JSON.stringify({
                ok: false,
                error: live.error ?? "stripe_live_blocked",
                message:
                  "Checkout LIVE bloqueado até GO / piloto + STRIPE_SECRET_KEY_LIVE.",
              }),
              {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }
          // ZIP 181: sem GO global, checkout LIVE só allowlist + teto + MONEY_GO.
          if (!isStripeLiveGlobalGo()) {
            const liveRows = (modeRows ?? []).filter((r) =>
              normalizeStripeMode(
                (r as { ops_stripe_mode?: string }).ops_stripe_mode,
              ) === "live"
            );
            for (const row of liveRows) {
              const sellerId = String(
                (row as { seller_id?: string }).seller_id ?? "",
              ).trim();
              const buyerId = String(
                (row as { buyer_id?: string }).buyer_id ??
                  body.buyer_id ??
                  "",
              ).trim();
              const paid = Number(
                (row as { amount_paid_cents?: number }).amount_paid_cents ?? 0,
              );
              const priceEur = Number(
                (row as { price_total?: number }).price_total ?? 0,
              );
              // F-001 / ZIP 190.1: NUNCA usar body.amount no gate piloto LIVE.
              // O cliente pode sub-declarar para furar max_total_cents; o PI real
              // já é cotado no servidor — o teto deve usar só BD (pago ou price_total).
              const totalCents = paid > 0
                ? Math.floor(paid)
                : Math.round(priceEur * 100);
              const gate = assertStripeLivePilotCheckout({
                sellerId,
                buyerId,
                totalCents,
              });
              if (!gate.ok) {
                return new Response(
                  JSON.stringify({
                    ok: false,
                    error: gate.error ?? "stripe_live_pilot_blocked",
                    needs_money_confirmation:
                      gate.needs_money_confirmation === true,
                    max_total_cents: gate.max_total_cents ?? null,
                    order_id: (row as { id?: string }).id ?? null,
                    total_cents_evaluated: totalCents,
                    message: gate.needs_money_confirmation
                      ? "Checkout LIVE piloto à espera de confirmação de valor (MONEY_GO)."
                      : "Checkout LIVE piloto bloqueado (allowlist/teto).",
                  }),
                  {
                    status: 403,
                    headers: {
                      ...corsHeaders,
                      "Content-Type": "application/json",
                    },
                  },
                );
              }
            }
          }
          stripe = new Stripe(live.key, {
            apiVersion: "2024-06-20",
            httpClient: Stripe.createFetchHttpClient(),
          });
          activeStripeMode = "live";
        }
      }
    }
    void activeStripeMode;

    // Log cedo (service role) — permite auditar FAIL Chrome mesmo se auth/amount falhar.
    if (serviceRoleKey) {
      const supabaseEarly = createClient(supabaseUrl, serviceRoleKey);
      await logStripeCheckoutEvent(supabaseEarly, "checkout_request", {
        order_id: body.order_id ?? null,
        product_id: body.product_id ?? null,
        live_id: body.live_id ?? null,
        buyer_id: body.buyer_id ?? null,
        amount: body.amount ?? null,
        bag_checkout: isBagCheckout,
        has_web_return_origin:
          typeof body.web_return_origin === "string" &&
          body.web_return_origin.trim().length > 0,
        prize_shipping: body.prize_shipping === true,
      });
    }

    let amount = 0;
    // product/seller derivados da order; body.amount / line_total não mandam.
    // Bag: order_id no body é opcional (linhas em bag_lines).
    if (!body.buyer_id || (!isBagCheckout && !body.order_id)) {
      throw new Error("Missing payment metadata.");
    }
    if (!serviceRoleKey) {
      throw new Error("Supabase service role is not configured.");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing authorization.");
    }
    const supabaseForAuth = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await supabaseForAuth.auth.getUser();
    if (userError || !user || user.id !== body.buyer_id) {
      throw new Error("Invalid checkout user.");
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // ZIP 140 — PaymentIntent separado para diferença de portes (não é nova venda).
    if (String((body as { mode?: string }).mode ?? "") === "shipping_delta") {
      const adjId = String(
        (body as { adjustment_id?: string }).adjustment_id ?? "",
      ).trim();
      const orderIdDelta = String(body.order_id ?? "").trim();
      if (!adjId || !orderIdDelta) {
        throw new Error("Missing adjustment_id / order_id.");
      }
      // ZIP 144.2: service_role sem GRANT SELECT em fleaber_feature_flags —
      // usar RPC security definer (igual às flags batata no SQL).
      const { data: flagOn, error: flagErr } = await supabaseAdmin.rpc(
        "batata_flag_enabled",
        { p_key: "order_shipping_delta_enabled" },
      );
      if (flagErr || flagOn !== true) {
        return new Response(
          JSON.stringify({
            error: "shipping_delta_disabled",
            message: "Pagamento de diferença de portes ainda não está activo.",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      const { data: adj, error: adjErr } = await supabaseAdmin
        .from("order_shipping_adjustments")
        .select("*")
        .eq("id", adjId)
        .eq("order_id", orderIdDelta)
        .maybeSingle();
      if (adjErr || !adj) throw new Error("Adjustment not found.");
      if (String(adj.buyer_id) !== user.id) {
        throw new Error("Invalid checkout user.");
      }
      if (String(adj.status) !== "pending") {
        throw new Error("Adjustment is not payable.");
      }
      if (new Date(String(adj.expires_at)).getTime() <= Date.now()) {
        throw new Error("Adjustment expired.");
      }
      const chargeCents = Number(adj.amount_charge_cents ?? 0);
      if (!Number.isInteger(chargeCents) || chargeCents < 50) {
        throw new Error("Invalid delta amount.");
      }
      // Reutilizar session open idempotente
      const priorSid = String(adj.stripe_checkout_session_id ?? "").trim();
      if (priorSid.startsWith("cs_")) {
        try {
          const prior = await stripe.checkout.sessions.retrieve(priorSid);
          if (
            prior.status === "open" &&
            prior.url &&
            prior.payment_status !== "paid" &&
            Number(prior.amount_total ?? 0) === chargeCents
          ) {
            return new Response(
              JSON.stringify({
                checkoutUrl: prior.url,
                checkoutSessionId: prior.id,
                fleaber_mode: "shipping_delta",
                server_amount_cents: chargeCents,
                shipping_delta_cents: adj.shipping_delta_cents,
                stripe_fee_grossup_cents: adj.stripe_fee_grossup_cents,
              }),
              {
                headers: { ...corsHeaders, "Content-Type": "application/json" },
                status: 200,
              },
            );
          }
        } catch { /* create new */ }
      }
      const functionUrl =
        `${supabaseUrl.replace(/\/$/, "")}/functions/v1/create-payment-intent`;
      const pmTypes = ["card"];
      // MB WAY se a conta Stripe o permitir — falha graceful se o create rejeitar.
      if ((Deno.env.get("STRIPE_DELTA_ALLOW_MBWAY") ?? "").trim() === "1") {
        pmTypes.push("mb_way");
      }
      const feeGross = Number(adj.stripe_fee_grossup_cents ?? 0);
      const deltaLabel = feeGross > 0
        ? `Diferença portes DPD (${adj.band_from}→${adj.band_to}) + processamento`
        : `Diferença portes DPD (${adj.band_from}→${adj.band_to})`;
      const deltaDesc = feeGross > 0
        ? `Portes ${Number(adj.shipping_delta_cents) / 100} € + taxa Stripe ${feeGross / 100} €. Sem Proteção Fleaber.`
        : `Portes ${Number(adj.shipping_delta_cents) / 100} €. Sem taxa Stripe extra ao comprador (PSD2). Sem Proteção Fleaber.`;
      let checkoutSession;
      try {
        checkoutSession = await stripe.checkout.sessions.create({
          mode: "payment",
          payment_method_types: pmTypes as Stripe.Checkout.SessionCreateParams.PaymentMethodType[],
          payment_method_options: {
            card: { request_three_d_secure: "automatic" },
          },
          success_url:
            `${functionUrl}?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
          cancel_url:
            `${functionUrl}?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
          line_items: [{
            quantity: 1,
            price_data: {
              currency: "eur",
              unit_amount: chargeCents,
              product_data: {
                name: deltaLabel,
                description: deltaDesc,
              },
            },
          }],
          metadata: {
            fleaber_mode: "shipping_delta",
            order_id: orderIdDelta,
            adjustment_id: adjId,
            buyer_id: user.id,
            seller_id: String(adj.seller_id ?? ""),
            shipping_delta_cents: String(adj.shipping_delta_cents ?? ""),
            stripe_fee_grossup_cents: String(adj.stripe_fee_grossup_cents ?? "0"),
            fleaber_protection_cents: "0",
            settle_as_sale: "false",
          },
          payment_intent_data: {
            metadata: {
              fleaber_mode: "shipping_delta",
              order_id: orderIdDelta,
              adjustment_id: adjId,
              buyer_id: user.id,
              seller_id: String(adj.seller_id ?? ""),
              settle_as_sale: "false",
            },
          },
        }, {
          idempotencyKey: `fleaber_delta_${adjId}`,
        });
      } catch (e) {
        // Retry só card se mb_way não suportado
        if (pmTypes.includes("mb_way")) {
          checkoutSession = await stripe.checkout.sessions.create({
            mode: "payment",
            payment_method_types: ["card"],
            payment_method_options: {
              card: { request_three_d_secure: "automatic" },
            },
            success_url:
              `${functionUrl}?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
            cancel_url:
              `${functionUrl}?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
            line_items: [{
              quantity: 1,
              price_data: {
                currency: "eur",
                unit_amount: chargeCents,
                product_data: {
                  name: deltaLabel,
                  description: deltaDesc,
                },
              },
            }],
            metadata: {
              fleaber_mode: "shipping_delta",
              order_id: orderIdDelta,
              adjustment_id: adjId,
              buyer_id: user.id,
              seller_id: String(adj.seller_id ?? ""),
              shipping_delta_cents: String(adj.shipping_delta_cents ?? ""),
              stripe_fee_grossup_cents: String(
                adj.stripe_fee_grossup_cents ?? "0",
              ),
              fleaber_protection_cents: "0",
              settle_as_sale: "false",
            },
            payment_intent_data: {
              metadata: {
                fleaber_mode: "shipping_delta",
                order_id: orderIdDelta,
                adjustment_id: adjId,
                buyer_id: user.id,
                seller_id: String(adj.seller_id ?? ""),
                settle_as_sale: "false",
              },
            },
          }, {
            idempotencyKey: `fleaber_delta_card_${adjId}`,
          });
        } else {
          throw e;
        }
      }
      await supabaseAdmin.from("order_shipping_adjustments").update({
        stripe_checkout_session_id: checkoutSession.id,
        updated_at: new Date().toISOString(),
      }).eq("id", adjId);

      return new Response(
        JSON.stringify({
          checkoutUrl: checkoutSession.url,
          checkoutSessionId: checkoutSession.id,
          fleaber_mode: "shipping_delta",
          server_amount_cents: chargeCents,
          shipping_delta_cents: adj.shipping_delta_cents,
          stripe_fee_grossup_cents: adj.stripe_fee_grossup_cents,
          amount_breakdown: {
            shipping_delta_eur: Number(adj.shipping_delta_cents) / 100,
            stripe_fee_grossup_eur: Number(adj.stripe_fee_grossup_cents) / 100,
            total_eur: chargeCents / 100,
            fleaber_protection_eur: 0,
          },
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    // SEC-006c: anti-spam só — fail-open. 60/h >> uso real (não bloqueia checkout normal).
    const checkoutBurst = await checkAnonRate(
      supabaseAdmin,
      `create_payment_intent:${user.id}`,
      "create-payment-intent-post",
      60,
    );
    if (checkoutBurst.rateLimited) {
      return new Response(
        JSON.stringify({ error: "Demasiados checkouts. Tenta daqui a pouco." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // P0-01 trust boundary: ORDER → preço (product/live/prize/qty do body não mandam).
    const quote = await resolveServerCheckoutQuote(
      supabaseAdmin,
      body,
      isBagCheckout,
      bagLines,
      user.id,
    );
    amount = quote.amountCents;
    if (!Number.isInteger(amount) || amount < 50) {
      throw new Error("Invalid payment amount.");
    }
    if (!quote.authProductId || !quote.authSellerId) {
      throw new Error("Checkout blocked: order missing product/seller.");
    }

    const clientClaimed = Number(body.amount ?? 0);
    if (
      Number.isFinite(clientClaimed) &&
      clientClaimed > 0 &&
      Math.abs(clientClaimed - amount) > 200
    ) {
      await logStripeCheckoutEvent(supabaseAdmin, "sec_fase1_client_amount_ignored", {
        order_id: quote.authOrderId,
        buyer_id: user.id,
        client_amount_cents: clientClaimed,
        server_amount_cents: amount,
        bag: isBagCheckout,
      });
    }

    // Alinha price_total na BD ao total servidor (fonte de verdade pós-checkout).
    try {
      if (isBagCheckout && quote.lineQuotes.length > 0) {
        const items = Math.max(quote.itemsCents, 1);
        let allocated = 0;
        for (let i = 0; i < quote.lineQuotes.length; i++) {
          const lq = quote.lineQuotes[i];
          const oid = lq.order_id?.trim() ?? "";
          if (!oid) continue;
          let share: number;
          if (i === quote.lineQuotes.length - 1) {
            share = amount - allocated;
          } else {
            share = Math.round((amount * lq.line_items_cents) / items);
            allocated += share;
          }
          await supabaseAdmin
            .from("orders")
            .update({ price_total: share / 100 })
            .eq("id", oid)
            .eq("buyer_id", user.id);
        }
      } else if (quote.authOrderId) {
        await supabaseAdmin
          .from("orders")
          .update({ price_total: amount / 100 })
          .eq("id", quote.authOrderId)
          .eq("buyer_id", user.id);
      }
    } catch (e) {
      console.warn("sec_fase1_price_total_align_failed", e);
    }

    const functionUrl = `${supabaseUrl}/functions/v1/create-payment-intent`;

    const lineItems = [
      {
        price_data: {
          currency,
          product_data: {
            name: quote.isPrizeShipping
              ? "Envio — Prémio da Rifa"
              : isBagCheckout
              ? "Saco Fleaber"
              : "Compra Fleaber",
          },
          unit_amount: amount,
        },
        quantity: 1,
      },
    ];

    const webReturnOrigin = sanitizeWebReturnOrigin(body.web_return_origin) ??
      "";

    const metadata: Record<string, string> = {
      product_id: quote.authProductId,
      buyer_id: user.id,
      seller_id: quote.authSellerId,
      order_id: quote.authOrderId,
      total: String(amount),
      server_amount_cents: String(amount),
      item_price: String(quote.itemsCents),
      shipping: String(quote.shippingCents),
      protection_fee: String(quote.protectionCents),
      shipping_method: body.shipping_method ?? "",
      live_id: quote.authLiveId || (body.live_id ?? ""),
      playback_id: body.playback_id ?? "",
      is_live: body.is_live == null ? "" : String(body.is_live),
      live_seller_id: quote.authSellerId,
      live_item_id: quote.authLiveItemId,
      reservation_request_id: body.reservation_request_id ?? "",
      checkout_attempt_id: String(body.checkout_attempt_id ?? "").trim(),
      prize_shipping: quote.isPrizeShipping ? "1" : "",
      ...(webReturnOrigin.length > 0
        ? { web_return_origin: webReturnOrigin }
        : {}),
    };
    if (isBagCheckout) {
      Object.assign(
        metadata,
        compactBagStripeMetadata(
          quote.lineQuotes.map((lq) => {
            const match = bagLines.find((b) =>
              (b.order_id ?? "").trim() === (lq.order_id ?? "").trim()
            );
            return {
              order_id: lq.order_id,
              product_id: lq.product_id,
              live_item_id: lq.live_item_id,
              reservation_request_id: match?.reservation_request_id,
            };
          }),
        ),
      );
    }

    // CHAT-MULTI: chat dedicado a ESTA encomenda antes do pagamento.
    if (
      !isBagCheckout &&
      quote.authOrderId &&
      quote.authProductId &&
      user.id &&
      quote.authSellerId &&
      !quote.authLiveId
    ) {
      try {
        const { data: dedicatedChat, error: dedicatedErr } = await supabaseAdmin
          .from("chats")
          .insert({
            user_a: user.id,
            user_b: quote.authSellerId,
            product_id: quote.authProductId,
          })
          .select("id")
          .single();
        if (!dedicatedErr && dedicatedChat?.id) {
          metadata.paid_chat_id = String(dedicatedChat.id);
        } else if (dedicatedErr) {
          console.error("CHAT_MULTI dedicated chat failed", dedicatedErr);
        }
      } catch (e) {
        console.error("CHAT_MULTI dedicated chat exception", e);
      }
    }

    // RTBB-1115-P1 / Indep P2 / RTI1606-P2-01: 1 order → 1 Session.
    // Claim atómico (FOR UPDATE) evita 2 cs_ em POST paralelo.
    let singleClaimToken = "";
    if (!isBagCheckout && quote.authOrderId) {
      singleClaimToken = `claiming:${Date.now()}:${crypto.randomUUID()}`;
      const claimToken = singleClaimToken;
      const { data: claimRaw, error: claimErr } = await supabaseAdmin.rpc(
        "batata_bag_checkout_claim",
        {
          p_order_ids: [quote.authOrderId],
          p_claim_token: claimToken,
        },
      );
      if (claimErr) {
        console.error("claim_checkout_session_slot", claimErr);
        throw new Error("Checkout blocked: could not lock order session.");
      }
      const claim = (claimRaw ?? {}) as Record<string, unknown>;
      const claimAction = String(claim.action ?? "");
      const claimSid = String(claim.session_id ?? "").trim();

      async function returnOpenSession(sid: string) {
        let prior: Stripe.Checkout.Session;
        try {
          prior = await stripe.checkout.sessions.retrieve(sid);
        } catch {
          // CJ-P2: cs_ morta/inválida → limpar e permitir novo claim
          await supabaseAdmin
            .from("orders")
            .update({ stripe_checkout_session_id: null })
            .eq("id", quote.authOrderId)
            .eq("stripe_checkout_session_id", sid);
          return null;
        }
        if (prior.payment_status === "paid") {
          throw new Error(
            "Checkout blocked: order already has a paid Stripe session.",
          );
        }
        const priorCurrency = String(prior.currency ?? "eur").trim().toLowerCase();
        const bagMeta =
          String(prior.metadata?.bag_checkout ?? "") === "true" ||
          String(prior.metadata?.bag_order_ids ?? "")
            .split(",")
            .map((s) => s.trim())
            .filter(Boolean).length > 1;
        if (bagMeta || bagSessionIncludesOrder(prior, quote.authOrderId ?? "")) {
          // DN/OPEN: Session de saco open nesta linha → sempre reutilizar (nunca dual)
          if (prior.status === "open" && prior.url) {
            await logStripeCheckoutEvent(
              supabaseAdmin,
              "checkout_session_reused",
              {
                session_id: prior.id,
                order_id: quote.authOrderId,
                buyer_id: user.id,
                amount: prior.amount_total ?? amount,
                reused_from: "bag_covers_single",
              },
            );
            return new Response(
              JSON.stringify({
                checkoutUrl: prior.url,
                checkoutSessionId: prior.id,
                paidChatId: metadata.paid_chat_id ?? null,
                server_amount_cents: prior.amount_total ?? amount,
                amount_total: prior.amount_total ?? amount,
                reused_session: true,
              }),
              {
                headers: {
                  ...corsHeaders,
                  "Content-Type": "application/json",
                },
                status: 200,
              },
            );
          }
          // Saco morto/não-open → não criar avulso por cima; contention
          throw new Error("Checkout blocked: overlapping bag session.");
        }
        if (priorCurrency !== currency) {
          // OPEN: nunca expire+criar por cima
          if (prior.status === "open") {
            throw new Error("Checkout blocked: overlapping bag session.");
          }
          await expireSharedBagCheckoutSession(stripe, supabaseAdmin, prior);
          return null;
        }
        if (prior.amount_total !== amount) {
          // OPEN: nunca expirar Session open da mesma order para criar outra
          if (prior.status === "open" && prior.url) {
            throw new Error("Checkout blocked: overlapping bag session.");
          }
          await expireSharedBagCheckoutSession(stripe, supabaseAdmin, prior);
          return null;
        }
        if (prior.status === "open" && prior.url) {
          await logStripeCheckoutEvent(
            supabaseAdmin,
            "checkout_session_reused",
            {
              session_id: prior.id,
              order_id: quote.authOrderId,
              buyer_id: user.id,
              amount,
            },
          );
          return new Response(
            JSON.stringify({
              checkoutUrl: prior.url,
              checkoutSessionId: prior.id,
              paidChatId: metadata.paid_chat_id ?? null,
              server_amount_cents: amount,
              amount_total: prior.amount_total ?? amount,
              reused_session: true,
            }),
            {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 200,
            },
          );
        }
        return null;
      }

      if (claimAction === "reuse" && claimSid.startsWith("cs_")) {
        const reused = await returnOpenSession(claimSid);
        if (reused) return reused;
        // Session morta → re-claim atómico (mutex + claiming), sem write solto
        const { data: reclaimRaw, error: reclaimErr } = await supabaseAdmin.rpc(
          "batata_bag_checkout_claim",
          {
            p_order_ids: [quote.authOrderId],
            p_claim_token: claimToken,
          },
        );
        if (reclaimErr) {
          console.error("single reclaim after dead cs_", reclaimErr);
          throw new Error("Checkout blocked: order claim busy.");
        }
        const reclaim = (reclaimRaw ?? {}) as Record<string, unknown>;
        const reclaimAction = String(reclaim.action ?? "");
        const reclaimSid = String(reclaim.session_id ?? "").trim();
        if (reclaimAction === "reuse" && reclaimSid.startsWith("cs_")) {
          const reused2 = await returnOpenSession(reclaimSid);
          if (reused2) return reused2;
          throw new Error("Checkout blocked: order claim contention.");
        }
        if (reclaimAction === "wait") {
          throw new Error("Checkout blocked: order claim contention.");
        }
        if (reclaimAction !== "create") {
          throw new Error("Checkout blocked: order claim contention.");
        }
      } else if (claimAction === "wait") {
        // Outro POST a criar — espera pela cs_ (bag∥single: qualquer pending do buyer)
        for (let i = 0; i < 40; i++) {
          await new Promise((r) => setTimeout(r, 200));
          const { data: waitRows } = await supabaseAdmin
            .from("orders")
            .select("id, stripe_checkout_session_id")
            .eq("buyer_id", user.id)
            .in("status", [...BAG_PENDING_STATUSES]);
          const sids = (waitRows ?? [])
            .map((row) => String(row.stripe_checkout_session_id ?? "").trim())
            .filter((s) => s.startsWith("cs_"));
          if (sids.length > 0) {
            const reused = await returnOpenSession(sids[0]!);
            if (reused) return reused;
            throw new Error("Checkout blocked: order claim contention.");
          }
        }
        // Timeout sem cs_: NÃO criar em paralelo — contention fail-closed
        throw new Error("Checkout blocked: order claim contention.");
      }
      // action === 'create' (ou reclaim) → criar Session abaixo; claimToken na row
    }

    // RTU-U3: saco — claim/reuse Session em todas as linhas (anti dual Session).
    const bagOrderIds = isBagCheckout
      ? quote.lineQuotes.map((lq) => lq.order_id).filter((id) =>
        (id ?? "").trim().length > 0
      )
      : [];
    let bagClaimToken = "";
    if (isBagCheckout && bagOrderIds.length > 0) {
      // GATE: NUNCA expire+criar 2.ª Session se já há cs_ open numa line do saco
      // (avulso ganhou a corrida → 400 overlapping / reuse; nunca matar+criar).
      for (const oid of bagOrderIds) {
        const { data: bagRow } = await supabaseAdmin
          .from("orders")
          .select("stripe_checkout_session_id")
          .eq("id", oid)
          .maybeSingle();
        const existingSid = String(bagRow?.stripe_checkout_session_id ?? "")
          .trim();
        if (existingSid.startsWith("cs_")) {
          let prior: Stripe.Checkout.Session;
          try {
            prior = await stripe.checkout.sessions.retrieve(existingSid);
          } catch {
            await supabaseAdmin
              .from("orders")
              .update({ stripe_checkout_session_id: null })
              .eq("id", oid)
              .eq("stripe_checkout_session_id", existingSid);
            continue;
          }
          if (prior.payment_status === "paid") {
            throw new Error(
              "Checkout blocked: bag already has a paid Stripe session.",
            );
          }
          const priorCurrency = String(prior.currency ?? "eur").trim()
            .toLowerCase();
          const priorBag = normalizeBagOrderIdsKey(
            String(prior.metadata?.bag_order_ids ?? ""),
          );
          const currentBag = normalizeBagOrderIdsKey(bagOrderIds);
          // Saco maior já aberto cobre o pedido → reutilizar
          if (
            priorCurrency === currency &&
            priorBag.length > 0 &&
            currentBag.length > 0 &&
            priorBag !== currentBag &&
            bagSetCovers(priorBag, currentBag) &&
            prior.status === "open" &&
            prior.url
          ) {
            return new Response(
              JSON.stringify({
                checkoutUrl: prior.url,
                checkoutSessionId: prior.id,
                paidChatId: metadata.paid_chat_id ?? null,
                server_amount_cents: prior.amount_total ?? amount,
                amount_total: prior.amount_total ?? amount,
                reused_session: true,
              }),
              {
                headers: { ...corsHeaders, "Content-Type": "application/json" },
                status: 200,
              },
            );
          }
          // Mesmo saco / mesma Session open → reutilizar
          if (
            priorCurrency === currency &&
            prior.amount_total === amount &&
            (priorBag.length === 0 || priorBag === currentBag) &&
            prior.status === "open" &&
            prior.url
          ) {
            return new Response(
              JSON.stringify({
                checkoutUrl: prior.url,
                checkoutSessionId: prior.id,
                paidChatId: metadata.paid_chat_id ?? null,
                server_amount_cents: amount,
                amount_total: prior.amount_total ?? amount,
                reused_session: true,
              }),
              {
                headers: { ...corsHeaders, "Content-Type": "application/json" },
                status: 200,
              },
            );
          }
          // Qualquer outra Session AINDA OPEN nesta line → fail-closed
          // (inclui avulso, amount mismatch, currency, expand, single leftover).
          // NUNCA expireShared + continue → isso era o dual A1/A2/A3.
          if (prior.status === "open") {
            throw new Error("Checkout blocked: overlapping bag session.");
          }
          // Só limpar Sessions mortas/não-open
          await expireSharedBagCheckoutSession(stripe, supabaseAdmin, prior);
        }
      }
      bagClaimToken = `claiming:${Date.now()}:${crypto.randomUUID()}`;
      let bagClaimReuseSid = "";
      // BR-P1: claim atómico FOR UPDATE em todos os ids do saco (anti race A∩B∩C)
      // IMPORTANTE: NÃO redeclarar bagClaimToken com `let` aqui — o write pós-create
      // usa o bagClaimToken do scope exterior; shadow = write sem eq(claim) = dual cs_.
      const runBagClaim = async (token: string): Promise<"create" | "reuse"> => {
        const { data: bagClaimRaw, error: bagClaimErr } = await supabaseAdmin.rpc(
          "batata_bag_checkout_claim",
          {
            p_order_ids: bagOrderIds,
            p_claim_token: token,
          },
        );
        if (bagClaimErr) {
          console.error("batata_bag_checkout_claim", bagClaimErr);
          throw new Error("Checkout blocked: could not lock bag session.");
        }
        const bagClaim = (bagClaimRaw ?? {}) as Record<string, unknown>;
        const bagAction = String(bagClaim.action ?? "");
        const bagSid = String(bagClaim.session_id ?? "").trim();
        if (bagAction === "reuse" && bagSid.startsWith("cs_")) {
          bagClaimReuseSid = bagSid;
          return "reuse";
        }
        if (bagAction === "wait") {
          for (let i = 0; i < 40; i++) {
            await new Promise((r) => setTimeout(r, 200));
            const { data: rows } = await supabaseAdmin
              .from("orders")
              .select("stripe_checkout_session_id")
              .eq("buyer_id", user.id)
              .in("status", [...BAG_PENDING_STATUSES]);
            const cs = (rows ?? [])
              .map((row) => String(row.stripe_checkout_session_id ?? "").trim())
              .filter((s) => s.startsWith("cs_"));
            if (cs.length > 0) {
              bagClaimReuseSid = cs[0]!;
              return "reuse";
            }
          }
          // Timeout sem cs_: fail-closed (não re-claim create em paralelo)
          throw new Error("Checkout blocked: bag claim contention.");
        }
        if (bagAction !== "create") {
          throw new Error("Checkout blocked: unexpected bag claim action.");
        }
        return "create";
      };
      await runBagClaim(bagClaimToken);
      // Expand/reuse: até 3 ciclos — nunca criar Session sem claim `create` activo
      for (let bagCycle = 0; bagCycle < 3; bagCycle++) {
        if (!bagClaimReuseSid.startsWith("cs_")) break;
        const prior = await stripe.checkout.sessions.retrieve(bagClaimReuseSid);
        if (prior.payment_status === "paid") {
          throw new Error(
            "Checkout blocked: bag already has a paid Stripe session.",
          );
        }
        const priorCurrency = String(prior.currency ?? "eur").trim()
          .toLowerCase();
        const priorBag = normalizeBagOrderIdsKey(
          String(prior.metadata?.bag_order_ids ?? ""),
        );
        const currentBag = normalizeBagOrderIdsKey(bagOrderIds);
        if (
          priorCurrency === currency &&
          prior.amount_total === amount &&
          (priorBag.length === 0 || priorBag === currentBag) &&
          prior.status === "open" &&
          prior.url
        ) {
          return new Response(
            JSON.stringify({
              checkoutUrl: prior.url,
              checkoutSessionId: prior.id,
              paidChatId: metadata.paid_chat_id ?? null,
              server_amount_cents: amount,
              amount_total: prior.amount_total ?? amount,
              reused_session: true,
            }),
            {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 200,
            },
          );
        }
        // DH/DN: saco maior cobre o pedido → reutilizar (não expirar+criar)
        if (
          priorCurrency === currency &&
          priorBag.length > 0 &&
          bagSetCovers(priorBag, currentBag) &&
          prior.status === "open" &&
          prior.url
        ) {
          return new Response(
            JSON.stringify({
              checkoutUrl: prior.url,
              checkoutSessionId: prior.id,
              paidChatId: metadata.paid_chat_id ?? null,
              server_amount_cents: prior.amount_total ?? amount,
              amount_total: prior.amount_total ?? amount,
              reused_session: true,
            }),
            {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 200,
            },
          );
        }
        // OPEN: expand (current ⊇ prior) → fail-closed, nunca expire+criar 2.ª Session
        if (
          priorBag.length > 0 &&
          currentBag.length > 0 &&
          bagSetCovers(currentBag, priorBag) &&
          priorBag !== currentBag
        ) {
          throw new Error("Checkout blocked: overlapping bag session.");
        }
        if (
          priorBag.length > 0 &&
          currentBag.length > 0 &&
          priorBag !== currentBag &&
          bagSetsOverlap(priorBag, currentBag)
        ) {
          throw new Error("Checkout blocked: overlapping bag session.");
        }
        if (prior.status === "open" && prior.url) {
          // DN P1: já há Session nestas lines (metadata vazia/parcial) →
          // reutilizar — nunca expirar+criar 2.ª Session
          return new Response(
            JSON.stringify({
              checkoutUrl: prior.url,
              checkoutSessionId: prior.id,
              paidChatId: metadata.paid_chat_id ?? null,
              server_amount_cents: prior.amount_total ?? amount,
              amount_total: prior.amount_total ?? amount,
              reused_session: true,
            }),
            {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 200,
            },
          );
        }
        // Session morta/não-open → limpar e re-claim create
        await expireSharedBagCheckoutSession(stripe, supabaseAdmin, prior);
        bagClaimReuseSid = "";
        bagClaimToken = `claiming:${Date.now()}:${crypto.randomUUID()}`;
        await runBagClaim(bagClaimToken);
      }
      if (bagClaimReuseSid.startsWith("cs_")) {
        throw new Error("Checkout blocked: bag claim contention.");
      }

      // DN: última guarda antes de criar — se alguma line já tem cs_ open, reutilizar
      {
        const { data: preRows } = await supabaseAdmin
          .from("orders")
          .select("id, stripe_checkout_session_id")
          .in("id", bagOrderIds);
        const preCs = (preRows ?? [])
          .map((row) => String(row.stripe_checkout_session_id ?? "").trim())
          .filter((s) => s.startsWith("cs_"));
        if (preCs.length > 0) {
          try {
            const prior = await stripe.checkout.sessions.retrieve(preCs[0]!);
            if (
              prior.status === "open" &&
              prior.url &&
              prior.payment_status !== "paid"
            ) {
              return new Response(
                JSON.stringify({
                  checkoutUrl: prior.url,
                  checkoutSessionId: prior.id,
                  paidChatId: metadata.paid_chat_id ?? null,
                  server_amount_cents: prior.amount_total ?? amount,
                  amount_total: prior.amount_total ?? amount,
                  reused_session: true,
                }),
                {
                  headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json",
                  },
                  status: 200,
                },
              );
            }
          } catch (e) {
            console.error("precreate bag sid guard", e);
          }
          throw new Error("Checkout blocked: bag claim contention.");
        }
        const foreignClaim = (preRows ?? []).some((row) => {
          const s = String(row.stripe_checkout_session_id ?? "").trim();
          return s.startsWith("claiming:") && s !== bagClaimToken;
        });
        if (foreignClaim) {
          throw new Error("Checkout blocked: bag claim contention.");
        }
      }

      // BF-P1 / DH: Sessions abertas nas lines — subset→reuse já feito; expand→expire; overlap→fail
      const currentBagKey = normalizeBagOrderIdsKey(bagOrderIds);
      for (const oid of bagOrderIds) {
        const { data: row } = await supabaseAdmin
          .from("orders")
          .select("stripe_checkout_session_id")
          .eq("id", oid)
          .maybeSingle();
        const sid = String(row?.stripe_checkout_session_id ?? "").trim();
        if (!sid.startsWith("cs_")) continue;
        try {
          const prior = await stripe.checkout.sessions.retrieve(sid);
          if (prior.status !== "open" || prior.payment_status === "paid") {
            continue;
          }
          const priorBag = normalizeBagOrderIdsKey(
            String(prior.metadata?.bag_order_ids ?? ""),
          );
          if (priorBag.length === 0 || priorBag === currentBagKey) continue;
          if (bagSetCovers(priorBag, currentBagKey) && prior.url) {
            return new Response(
              JSON.stringify({
                checkoutUrl: prior.url,
                checkoutSessionId: prior.id,
                paidChatId: metadata.paid_chat_id ?? null,
                server_amount_cents: prior.amount_total ?? amount,
                amount_total: prior.amount_total ?? amount,
                reused_session: true,
              }),
              {
                headers: { ...corsHeaders, "Content-Type": "application/json" },
                status: 200,
              },
            );
          }
          if (bagSetCovers(currentBagKey, priorBag)) {
            // OPEN: nunca expire+criar — overlap/expand = contention
            throw new Error("Checkout blocked: overlapping bag session.");
          }
          if (bagSetsOverlap(priorBag, currentBagKey)) {
            throw new Error("Checkout blocked: overlapping bag session.");
          }
        } catch (e) {
          if (String(e).includes("overlapping bag session")) throw e;
          console.error("bag overlap expire", sid, e);
        }
      }
    }

    // DN / OPEN: guarda single — cs_ nesta order OU saco open que a inclui
    if (!isBagCheckout && quote.authOrderId) {
      const { data: preSingle } = await supabaseAdmin
        .from("orders")
        .select("stripe_checkout_session_id")
        .eq("id", quote.authOrderId)
        .maybeSingle();
      const preSid = String(preSingle?.stripe_checkout_session_id ?? "").trim();
      if (preSid.startsWith("cs_")) {
        try {
          const prior = await stripe.checkout.sessions.retrieve(preSid);
          if (
            prior.status === "open" &&
            prior.url &&
            prior.payment_status !== "paid"
          ) {
            return new Response(
              JSON.stringify({
                checkoutUrl: prior.url,
                checkoutSessionId: prior.id,
                paidChatId: metadata.paid_chat_id ?? null,
                server_amount_cents: prior.amount_total ?? amount,
                amount_total: prior.amount_total ?? amount,
                reused_session: true,
              }),
              {
                headers: {
                  ...corsHeaders,
                  "Content-Type": "application/json",
                },
                status: 200,
              },
            );
          }
        } catch (_) {
          /* fall through to contention */
        }
        throw new Error("Checkout blocked: order claim contention.");
      }
      if (
        preSid.startsWith("claiming:") &&
        singleClaimToken &&
        preSid !== singleClaimToken
      ) {
        throw new Error("Checkout blocked: order claim contention.");
      }
      // OPEN bag∥single: outro pedido do buyer com Session de saco que inclui esta line
      if (user?.id) {
        const { data: sibs } = await supabaseAdmin
          .from("orders")
          .select("id, stripe_checkout_session_id")
          .eq("buyer_id", user.id)
          .in("status", [...BAG_PENDING_STATUSES])
          .not("stripe_checkout_session_id", "is", null);
        const seen = new Set<string>();
        for (const row of sibs ?? []) {
          const sid = String(row.stripe_checkout_session_id ?? "").trim();
          if (!sid.startsWith("cs_") || seen.has(sid)) continue;
          seen.add(sid);
          try {
            const prior = await stripe.checkout.sessions.retrieve(sid);
            if (
              prior.status !== "open" ||
              !prior.url ||
              prior.payment_status === "paid"
            ) {
              continue;
            }
            if (bagSessionIncludesOrder(prior, quote.authOrderId)) {
              return new Response(
                JSON.stringify({
                  checkoutUrl: prior.url,
                  checkoutSessionId: prior.id,
                  paidChatId: metadata.paid_chat_id ?? null,
                  server_amount_cents: prior.amount_total ?? amount,
                  amount_total: prior.amount_total ?? amount,
                  reused_session: true,
                }),
                {
                  headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json",
                  },
                  status: 200,
                },
              );
            }
          } catch (_) {
            /* ignore */
          }
        }
      }
    }

    // OPEN: última guarda buyer-wide antes de Stripe — claiming alheio → wait/contention
    // Cobre bag∥single a frio (1.º tiro) quando os dois já passaram o claim create.
    const ourTok = user?.id
      ? (isBagCheckout
        ? (typeof bagClaimToken === "string" ? bagClaimToken : "")
        : (typeof singleClaimToken === "string" ? singleClaimToken : ""))
      : "";
    if (user?.id) {
      for (let i = 0; i < 40; i++) {
        const { data: busyRows } = await supabaseAdmin
          .from("orders")
          .select("id, stripe_checkout_session_id")
          .eq("buyer_id", user.id)
          .in("status", [...BAG_PENDING_STATUSES]);
        // Qualquer cs_ pending do buyer → reutilizar (não só nas ourIds)
        const anyCs = (busyRows ?? [])
          .map((row) => String(row.stripe_checkout_session_id ?? "").trim())
          .filter((s) => s.startsWith("cs_"));
        if (anyCs.length > 0) {
          try {
            const prior = await stripe.checkout.sessions.retrieve(anyCs[0]!);
            if (
              prior.status === "open" &&
              prior.url &&
              prior.payment_status !== "paid"
            ) {
              return new Response(
                JSON.stringify({
                  checkoutUrl: prior.url,
                  checkoutSessionId: prior.id,
                  paidChatId: metadata.paid_chat_id ?? null,
                  server_amount_cents: prior.amount_total ?? amount,
                  amount_total: prior.amount_total ?? amount,
                  reused_session: true,
                }),
                {
                  headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json",
                  },
                  status: 200,
                },
              );
            }
          } catch (_) {
            /* fall through */
          }
        }
        const foreign = (busyRows ?? []).some((row) => {
          const s = String(row.stripe_checkout_session_id ?? "").trim();
          return (
            s.startsWith("claiming:") &&
            ourTok.startsWith("claiming:") &&
            s !== ourTok
          );
        });
        if (!foreign) break;
        await new Promise((r) => setTimeout(r, 200));
      }
      {
        const { data: finalRows } = await supabaseAdmin
          .from("orders")
          .select("stripe_checkout_session_id")
          .eq("buyer_id", user.id)
          .in("status", [...BAG_PENDING_STATUSES]);
        const stillForeign = (finalRows ?? []).some((row) => {
          const s = String(row.stripe_checkout_session_id ?? "").trim();
          return (
            s.startsWith("claiming:") &&
            ourTok.startsWith("claiming:") &&
            s !== ourTok
          );
        });
        if (stillForeign) {
          throw new Error("Checkout blocked: overlapping bag session.");
        }
      }
    }

    // Gate definitivo: só 1 Stripe create por buyer em voo (may_create)
    if (user?.id && ourTok.startsWith("claiming:")) {
      for (let gateTry = 0; gateTry < 40; gateTry++) {
        const { data: mayRaw, error: mayErr } = await supabaseAdmin.rpc(
          "batata_buyer_may_create_session",
          {
            p_buyer_id: user.id,
            p_claim_token: ourTok,
          },
        );
        if (mayErr) {
          console.error("batata_buyer_may_create_session", mayErr);
          throw new Error("Checkout blocked: could not verify checkout gate.");
        }
        const may = (mayRaw ?? {}) as Record<string, unknown>;
        const mayAction = String(may.action ?? "");
        const maySid = String(may.session_id ?? "").trim();
        if (mayAction === "create") break;
        if (mayAction === "reuse" && maySid.startsWith("cs_")) {
          try {
            const prior = await stripe.checkout.sessions.retrieve(maySid);
            if (
              prior.status === "open" &&
              prior.url &&
              prior.payment_status !== "paid"
            ) {
              return new Response(
                JSON.stringify({
                  checkoutUrl: prior.url,
                  checkoutSessionId: prior.id,
                  paidChatId: metadata.paid_chat_id ?? null,
                  server_amount_cents: prior.amount_total ?? amount,
                  amount_total: prior.amount_total ?? amount,
                  reused_session: true,
                }),
                {
                  headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json",
                  },
                  status: 200,
                },
              );
            }
          } catch (_) {
            /* fall through to wait/deny */
          }
        }
        if (mayAction === "deny" && gateTry >= 5) {
          throw new Error("Checkout blocked: overlapping bag session.");
        }
        await new Promise((r) => setTimeout(r, 200));
        if (gateTry === 39) {
          throw new Error("Checkout blocked: overlapping bag session.");
        }
      }
    } else if (user?.id) {
      // Sem claim token → nunca criar Session (fail-closed)
      throw new Error("Checkout blocked: missing checkout claim.");
    }

    const checkoutSession = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      // ZIP 128: SCA / 3DS quando o emissor exigir (Radar + PSD2) — sem forçar always.
      payment_method_options: {
        card: {
          request_three_d_secure: "automatic",
        },
      },
      success_url:
        `${functionUrl}?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url:
        `${functionUrl}?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
      line_items: lineItems,
      metadata,
      // PI na session à criação → confirm sandbox + webhook settle sem browser.
      payment_intent_data: {
        metadata: {
          order_id: String(metadata.order_id ?? ""),
          buyer_id: String(metadata.buyer_id ?? ""),
          product_id: String(metadata.product_id ?? ""),
          checkout_attempt_id: String(metadata.checkout_attempt_id ?? ""),
        },
      },
    }, {
      // Retry do MESMO create (rede) — não dedupe bag vs single (params diferem).
      idempotencyKey: ourTok.startsWith("claiming:")
        ? `fleaber_cs_${ourTok.slice(0, 200)}`
        : `fleaber_cs_${user?.id ?? "anon"}_${crypto.randomUUID()}`,
    });

    await logStripeCheckoutEvent(supabaseAdmin, "checkout_session_created", {
      session_id: checkoutSession.id,
      order_id: quote.authOrderId,
      product_id: quote.authProductId,
      live_id: quote.authLiveId || null,
      buyer_id: user.id,
      amount,
      has_checkout_url: Boolean(checkoutSession.url),
      has_web_return_origin: webReturnOrigin.length > 0,
      paid_chat_id: metadata.paid_chat_id ?? null,
    });

    // RTBB-1115 / Indep P2: gravar Session na order (single) para reutilizar / auditar.
    // D1: se BD tinha shipping null e o body trouxe método válido, persistir selo
    // (Flutter já grava; atacante PostgREST omitia → null→mão pós-pago).
    if (!isBagCheckout && quote.authOrderId) {
      try {
        const shipBody = String(body.shipping_method ?? "").trim();
        const patch: Record<string, unknown> = {
          stripe_checkout_session_id: checkoutSession.id,
        };
        if (shipBody.length > 0) {
          const { data: cur } = await supabaseAdmin
            .from("orders")
            .select("shipping_method")
            .eq("id", quote.authOrderId)
            .maybeSingle();
          const curShip = String(cur?.shipping_method ?? "").trim();
          if (curShip.length === 0) {
            patch.shipping_method = shipBody;
          }
        }
        // OPEN bag∥single: só grava se o nosso claim ainda está (anti overwrite do saco)
        let singleUpd = supabaseAdmin
          .from("orders")
          .update(patch)
          .eq("id", quote.authOrderId)
          .in("status", [
            "reserva_pendente",
            "reservado",
            "aguarda_confirmacao",
            "aguarda_pagamento",
            "premio_rifa",
          ]);
        if (singleClaimToken.startsWith("claiming:")) {
          singleUpd = singleUpd.eq(
            "stripe_checkout_session_id",
            singleClaimToken,
          );
        }
        const { data: wroteSingle, error: writeSingleErr } = await singleUpd
          .select("id");
        if (writeSingleErr) {
          console.error("single session write", writeSingleErr);
        }
        if (
          singleClaimToken.startsWith("claiming:") &&
          (wroteSingle ?? []).length < 1
        ) {
          try {
            await stripe.checkout.sessions.expire(checkoutSession.id);
          } catch (e) {
            console.error("expire orphan single session", e);
          }
          throw new Error("Checkout blocked: overlapping bag session.");
        }
        // NÃO libertar mutex aqui — finalize é o único release (anti dual create)
      } catch (e) {
        if (String(e).includes("overlapping bag session")) throw e;
        // Fail-closed: nunca devolver cs_ se a escrita falhou
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        throw e instanceof Error
          ? e
          : new Error("Checkout blocked: order session write failed.");
      }
    }

    if (isBagCheckout && bagOrderIds.length > 0) {
      // Só grava cs_ onde o nosso claim ainda está (anti 2.ª Session overlap)
      const claimTok = typeof bagClaimToken === "string" ? bagClaimToken : "";
      if (!claimTok.startsWith("claiming:")) {
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        throw new Error("Checkout blocked: missing bag claim.");
      }
      let upd = supabaseAdmin.from("orders").update({
        stripe_checkout_session_id: checkoutSession.id,
      }).in("id", bagOrderIds).in("status", [
        "reserva_pendente",
        "reservado",
        "aguarda_confirmacao",
        "aguarda_pagamento",
        "premio_rifa",
      ]).eq("stripe_checkout_session_id", claimTok);
      const { data: wrote, error: writeErr } = await upd.select("id");
      if (writeErr) {
        console.error("bag session write", writeErr);
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        throw new Error("Checkout blocked: bag session write failed.");
      }
      const wroteN = (wrote ?? []).length;
      if (wroteN < bagOrderIds.length) {
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (e) {
          console.error("expire orphan bag session", e);
        }
        throw new Error("Checkout blocked: bag claim contention.");
      }
      if (user?.id) {
        await expireOverlappingOpenSessionsForBuyer(
          stripe,
          supabaseAdmin,
          user.id,
          checkoutSession.id,
          bagOrderIds,
        );
      }
      // NÃO libertar mutex aqui — finalize é o único release
    }

    // Árbitro GLOBAL: 1 Session por buyer nos pending (bag∥single → mesmo sid / 400)
    if (user?.id && String(checkoutSession.id ?? "").startsWith("cs_")) {
      const finalizeIds = isBagCheckout
        ? bagOrderIds
        : (quote.authOrderId ? [quote.authOrderId] : []);
      if (finalizeIds.length < 1) {
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        throw new Error("Checkout blocked: missing finalize order ids.");
      }
      const { data: finRaw, error: finErr } = await supabaseAdmin.rpc(
        "batata_buyer_finalize_checkout",
        {
          p_buyer_id: user.id,
          p_keep_sid: checkoutSession.id,
          p_order_ids: finalizeIds,
        },
      );
      if (finErr) {
        console.error("batata_buyer_finalize_checkout", finErr);
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        throw new Error("Checkout blocked: finalize failed.");
      }
      const fin = (finRaw ?? {}) as Record<string, unknown>;
      if (fin.ok === false) {
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        throw new Error("Checkout blocked: finalize rejected.");
      }
      const expireSids = Array.isArray(fin.expire_sids)
        ? (fin.expire_sids as unknown[]).map((s) => String(s))
        : [];
      for (const sid of expireSids) {
        if (!sid.startsWith("cs_") || sid === checkoutSession.id) continue;
        try {
          await stripe.checkout.sessions.expire(sid);
        } catch (e) {
          console.error("finalize expire orphan", sid, e);
        }
      }
      const winner = String(fin.winner_sid ?? "").trim();
      const weWon = fin.we_won === true && winner === checkoutSession.id;
      if (!weWon) {
        try {
          await stripe.checkout.sessions.expire(checkoutSession.id);
        } catch (_) {
          /* best-effort */
        }
        if (winner.startsWith("cs_") && winner !== checkoutSession.id) {
          try {
            const prior = await stripe.checkout.sessions.retrieve(winner);
            if (
              prior.status === "open" &&
              prior.url &&
              prior.payment_status !== "paid"
            ) {
              return new Response(
                JSON.stringify({
                  checkoutUrl: prior.url,
                  checkoutSessionId: prior.id,
                  paidChatId: metadata.paid_chat_id ?? null,
                  server_amount_cents: prior.amount_total ?? amount,
                  amount_total: prior.amount_total ?? amount,
                  reused_session: true,
                }),
                {
                  headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json",
                  },
                  status: 200,
                },
              );
            }
          } catch (e) {
            console.error("finalize retrieve winner", winner, e);
          }
        }
        throw new Error("Checkout blocked: overlapping bag session.");
      }
    }

    return new Response(
      JSON.stringify({
        checkoutUrl: checkoutSession.url,
        checkoutSessionId: checkoutSession.id,
        paidChatId: metadata.paid_chat_id ?? null,
        // FASE1 smoke: prova do montante Stripe sem precisar da secret no cliente
        server_amount_cents: amount,
        amount_total: checkoutSession.amount_total ?? amount,
        reused_session: false,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (supabaseUrl && serviceRoleKey) {
        const supabaseLog = createClient(supabaseUrl, serviceRoleKey);
        await logStripeCheckoutEvent(supabaseLog, "checkout_error", {
          error: message,
        });
      }
    } catch (_) {
      // não mascarar o erro original
    }
    return new Response(
      JSON.stringify({
        error: message,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
