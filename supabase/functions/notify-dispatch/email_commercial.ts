/**
 * Ponto 7 — Emails comerciais E1–E3 + delta portes / prazos (ZIP 142 → C2).
 * Fotografias: só URLs vindas de products.image_urls (nunca inventar).
 * «Está a caminho»: só com handedToCarrier (ex. dpd_accept_at), não só etiqueta/guia.
 * Delta: nunca 2.ª Proteção Fleaber; nunca apresentar como nova compra/venda.
 */

export const HUB_ENCOMENDAS_URL =
  "https://fleaber.pt/fleahub/#/perfil?secao=encomendas";

const ORDER_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True se o valor é um UUID de encomenda utilizável no deep link. */
export function isOrderUuid(value: string | null | undefined): boolean {
  return ORDER_UUID_RE.test((value ?? "").trim());
}

/**
 * Deep link Hub/App para uma encomenda concreta (`?orderId=`).
 * Sem UUID válido → `null` (nunca a lista genérica).
 */
export function orderDeepLinkUrl(
  orderId: string | null | undefined,
): string | null {
  const id = (orderId ?? "").trim();
  if (!isOrderUuid(id)) return null;
  return `https://fleaber.pt/fleahub/#/perfil?secao=encomendas&orderId=${encodeURIComponent(id)}`;
}

export type CommercialEmailKind =
  | "order_paid_buyer"
  | "order_paid_seller"
  | "reservation_order_shipped"
  | "shipping_delta_requested"
  | "shipping_delta_paid"
  | "shipping_delta_expired_cancelled"
  | "ship_deadline_auto_cancelled"
  | "bundle_quote_ready"
  | "bundle_expired"
  | "bundle_quote_invalidated"
  | "bundle_proposal"
  | "bundle_purchase_request";

export const HUB_MENSAGENS_URL =
  "https://fleaber.pt/fleahub/#/listaConversas";

export type OrderLineEmail = {
  title: string;
  /** Preço unitário/linha formatado (ex. 18,00 €). */
  priceLabel?: string | null;
  qty?: number;
  /** URL https real de products.image_urls[0] — omitir se vazio. */
  imageUrl?: string | null;
};

export type OrderEmailContext = {
  orderId?: string | null;
  referenceLabel?: string | null;
  productTitle?: string | null;
  totalLabel?: string | null;
  statusLabel?: string | null;
  hasBuyerProtection?: boolean;
  shipmentConfirmed?: boolean;
  /** Aceite pela transportadora (ex. orders.dpd_accept_at). NÃO = só etiqueta. */
  handedToCarrier?: boolean;
  trackingCode?: string | null;
  trackingUrl?: string | null;
  carrierLabel?: string | null;
  /** Breakdown E1 — só se existir na BD (checkout attempt). */
  itemsTotalLabel?: string | null;
  shippingLabel?: string | null;
  protectionLabel?: string | null;
  lines?: OrderLineEmail[];
  /** Deep link encomenda específica — só se rota funcional existir. */
  ctaUrl?: string | null;
  /** ZIP 142 — diferença de portes / prazos (C2 templates). */
  deltaCents?: number | null;
  shippingDeltaCents?: number | null;
  stripeFeeGrossupCents?: number | null;
  amountChargeCents?: number | null;
  fleaberProtectionCents?: number | null;
  feePolicy?: string | null;
  weightBandFrom?: string | null;
  weightBandTo?: string | null;
  payDeadlineAt?: string | null;
  shipByAt?: string | null;
  adjustmentId?: string | null;
  refundHint?: string | null;
  /** Destinatário deste email (buyer|seller) — copia distinta em paid/cancel. */
  audienceRole?: "buyer" | "seller" | null;
  buyerId?: string | null;
  sellerId?: string | null;
  /** Cancelamentos: initiated | completed */
  refundStatus?: "initiated" | "completed" | string | null;
  /** ZIP 149 — conjuntos quote-before-pay (sem orderId pré-pagamento). */
  chatId?: string | null;
  bundleId?: string | null;
  payDeadlineLabel?: string | null;
  articlesTotalLabel?: string | null;
  grandTotalLabel?: string | null;
  /** Motivo de expiração / invalidação (ex. seller_confirm_timeout_48h). */
  expireReason?: string | null;
  confirmDeadlineLabel?: string | null;
};

export const DEFAULT_REFUND_HINT =
  "Reembolso integral dos pagamentos efetuados.";

export function canSendShippedEmail(ctx: OrderEmailContext): boolean {
  return ctx.shipmentConfirmed === true;
}

export function isBundleQuoteEmailKind(kind: string): boolean {
  const k = kind.trim().toLowerCase();
  return (
    k === "bundle_quote_ready" ||
    k === "bundle_expired" ||
    k === "bundle_quote_invalidated" ||
    k === "bundle_proposal" ||
    k === "bundle_purchase_request"
  );
}

export function wantsCommercialEmail(kind: string): boolean {
  const k = kind.trim().toLowerCase();
  return (
    k === "order_paid_buyer" ||
    k === "order_paid_seller" ||
    k === "reservation_order_shipped" ||
    k === "shipping_delta_requested" ||
    k === "shipping_delta_paid" ||
    k === "shipping_delta_expired_cancelled" ||
    k === "ship_deadline_auto_cancelled" ||
    isBundleQuoteEmailKind(k)
  );
}

export function bundleMensagensDeepLink(
  chatId: string | null | undefined,
): string {
  const id = (chatId ?? "").trim();
  if (!ORDER_UUID_RE.test(id)) return HUB_MENSAGENS_URL;
  return `${HUB_MENSAGENS_URL}?initialChatId=${encodeURIComponent(id)}`;
}

export function isShippingDeltaKind(kind: string): boolean {
  const k = kind.trim().toLowerCase();
  return (
    k === "shipping_delta_requested" ||
    k === "shipping_delta_paid" ||
    k === "shipping_delta_expired_cancelled" ||
    k === "ship_deadline_auto_cancelled"
  );
}

/** Infere audiência a partir do dedupe C1 (quando aplicável). */
export function audienceRoleFromDedupe(
  kind: string,
  dedupe: string | null | undefined,
): "buyer" | "seller" | null {
  const k = kind.trim().toLowerCase();
  const d = (dedupe ?? "").trim().toLowerCase();
  if (k === "shipping_delta_requested") return "buyer";
  if (k === "shipping_delta_paid") {
    if (d.endsWith(":paid:buyer")) return "buyer";
    if (d.endsWith(":paid")) return "seller";
  }
  return null;
}

export function weightBandLabel(band: string | null | undefined): string {
  switch ((band ?? "").trim()) {
    case "0_3":
      return "até 3 kg";
    case "3_6":
      return "3–6 kg";
    case "6_10":
      return "6–10 kg";
    default: {
      const b = (band ?? "").trim();
      return b || "—";
    }
  }
}

/** Datas sempre DD/MM/AAAA (opcionalmente com hora HH:MM) — Lisboa. */
export function formatDeadlinePt(
  iso: string | null | undefined,
  opts?: { withTime?: boolean },
): string | null {
  const s = (iso ?? "").trim();
  if (!s) return null;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat("pt-PT", {
      timeZone: "Europe/Lisbon",
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      ...(opts?.withTime === false
        ? {}
        : { hour: "2-digit", minute: "2-digit", hour12: false }),
    }).formatToParts(d);
    const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
    const date = `${get("day")}/${get("month")}/${get("year")}`;
    if (opts?.withTime === false) return date;
    const hh = get("hour");
    const mm = get("minute");
    return hh && mm ? `${date} ${hh}:${mm}` : date;
  } catch {
    const dd = String(d.getUTCDate()).padStart(2, "0");
    const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
    const yyyy = d.getUTCFullYear();
    return `${dd}/${mm}/${yyyy}`;
  }
}

/**
 * Prazo em linguagem natural PT-PT (Lisboa): «às 18h00 de 06/11/2026».
 * Usado nos emails de conjuntos — nunca datas fixas no template.
 */
export function formatDeadlineNaturalPt(
  iso: string | null | undefined,
): string | null {
  const s = (iso ?? "").trim();
  if (!s) return null;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat("pt-PT", {
      timeZone: "Europe/Lisbon",
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(d);
    const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
    const date = `${get("day")}/${get("month")}/${get("year")}`;
    const hh = get("hour");
    const mm = get("minute");
    if (!hh || !mm) return date;
    return `às ${hh}h${mm} de ${date}`;
  } catch {
    return formatDeadlinePt(iso);
  }
}

/** Texto de reembolso: iniciado vs concluído (nunca ambíguo). */
export function refundStatusCopy(opts: {
  refundStatus?: "initiated" | "completed" | string | null;
  refundHint?: string | null;
}): { title: string; body: string } {
  const st = (opts.refundStatus ?? "").trim().toLowerCase();
  if (st === "completed" || st === "refunded" || st === "done") {
    return {
      title: "Reembolso concluído",
      body: (opts.refundHint ?? "").trim() ||
        "O reembolso integral foi concluído. O valor deve aparecer na tua conta em breve, conforme o banco.",
    };
  }
  return {
    title: "Reembolso iniciado",
    body: (opts.refundHint ?? "").trim() ||
      "O reembolso integral foi iniciado. O valor será devolvido — o prazo depende do teu banco.",
  };
}

export function commercialSubject(
  kind: string,
  ctx: OrderEmailContext = {},
): string {
  switch (kind.trim().toLowerCase()) {
    case "order_paid_buyer":
      return "Já está! A tua compra na Fleaber foi confirmada";
    case "order_paid_seller":
      return "🎉 Parabéns! Fizeste uma venda na Fleaber!";
    case "reservation_order_shipped":
      return ctx.handedToCarrier === true
        ? "A tua encomenda está a caminho"
        : "O envio da tua encomenda foi confirmado";
    case "shipping_delta_requested":
      return "Diferença de portes a pagar na Fleaber";
    case "shipping_delta_paid":
      return ctx.audienceRole === "seller"
        ? "Diferença de portes paga — podes enviar"
        : "Diferença de portes confirmada";
    case "shipping_delta_expired_cancelled":
      return "Encomenda cancelada — diferença de portes não paga";
    case "ship_deadline_auto_cancelled":
      return "Encomenda cancelada — prazo de envio ultrapassado";
    case "bundle_quote_ready":
      return "Portes confirmados — já podes pagar o teu conjunto";
    case "bundle_expired": {
      const reason = (ctx.expireReason ?? "").toLowerCase();
      if (reason.includes("buyer_pay") || reason.includes("pay_timeout")) {
        return "O prazo para pagar terminou";
      }
      if (reason.includes("seller_confirm") || reason.includes("confirm_timeout")) {
        return "Pedido de conjunto expirado — portes não confirmados";
      }
      return "Pedido de conjunto expirado";
    }
    case "bundle_quote_invalidated":
      return "O teu conjunto já não está disponível";
    case "bundle_proposal":
    case "bundle_purchase_request":
      return "Novo pedido de conjunto na Fleaber";
    default:
      return "Fleaber";
  }
}

export function parseOrderIdFromDedupe(
  dedupe: string | null | undefined,
): string | null {
  const d = (dedupe ?? "").trim();
  if (!d) return null;
  let m = /^order_paid:([0-9a-f-]{36}):(?:buyer|seller)$/i.exec(d);
  if (m && isOrderUuid(m[1])) return m[1];
  m = /^shipped:([0-9a-f-]{36})$/i.exec(d);
  if (m && isOrderUuid(m[1])) return m[1];
  // Fallbacks seguros (live / conjunto / legado) — só se houver UUID válido.
  m = /(?:^|:)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?::|$)/i
    .exec(d);
  if (m && isOrderUuid(m[1])) return m[1];
  return null;
}

/** Resolve orderId a partir do contexto de despacho (dedupe + campos explícitos). */
export function resolveCommercialOrderId(opts: {
  dedupe?: string | null;
  orderId?: string | null;
  metaOrderId?: string | null;
}): string | null {
  if (isOrderUuid(opts.orderId)) return (opts.orderId ?? "").trim();
  if (isOrderUuid(opts.metaOrderId)) return (opts.metaOrderId ?? "").trim();
  return parseOrderIdFromDedupe(opts.dedupe);
}

export function shortRef(orderId: string | null | undefined): string {
  const id = (orderId ?? "").trim();
  if (!id) return "—";
  return id.replace(/-/g, "").slice(0, 8).toUpperCase();
}

export function formatEuro(value: number | null | undefined): string | null {
  if (value == null || Number.isNaN(value)) return null;
  return `${value.toFixed(2).replace(".", ",")} €`;
}

export function formatCents(cents: number | null | undefined): string | null {
  if (cents == null || Number.isNaN(cents)) return null;
  return formatEuro(cents / 100);
}

/** Aceita só http(s) — rejeita vazios / data: / placeholders. */
export function sanitizeImageUrl(url: string | null | undefined): string | null {
  const u = (url ?? "").trim();
  if (!u) return null;
  if (!/^https?:\/\//i.test(u)) return null;
  return u;
}

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function shell(opts: {
  headline: string;
  preheader: string;
  innerHtml: string;
  ctaLabel?: string | null;
  ctaUrl?: string | null;
}): string {
  const cta = opts.ctaLabel && opts.ctaUrl
    ? `<p style="margin:8px 0 28px;text-align:center;">
              <a href="${esc(opts.ctaUrl)}" style="display:inline-block;background:#007782;color:#ffffff;text-decoration:none;font-weight:700;padding:16px 28px;border-radius:16px;font-size:16px;">${esc(opts.ctaLabel)}</a>
            </p>`
    : `<p style="margin:0 0 20px;"></p>`;
  return `<!DOCTYPE html>
<html lang="pt-PT">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(opts.headline)}</title>
</head>
<body style="margin:0;padding:0;background:#F4F7F8;font-family:Arial,Helvetica,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(opts.preheader)}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F4F7F8;padding:28px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%;background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #D5E4E6;">
        <tr>
          <td style="background:#007782;padding:28px 32px;">
            <p style="margin:0;color:#FFFFFF;font-size:15px;letter-spacing:3px;text-transform:uppercase;font-weight:700;">Fleaber</p>
            <h1 style="margin:12px 0 0;color:#ffffff;font-size:24px;line-height:1.3;font-weight:700;">${esc(opts.headline)}</h1>
          </td>
        </tr>
        <tr>
          <td style="padding:28px 32px 8px;color:#101518;font-size:16px;line-height:1.55;">
            ${opts.innerHtml}
            ${cta}
          </td>
        </tr>
        <tr>
          <td style="padding:18px 32px 28px;border-top:1px solid #E8EEF0;color:#57636C;font-size:14px;line-height:1.55;">
            <strong style="color:#007782;">Fleaber</strong> · <a href="https://fleaber.pt" style="color:#007782;text-decoration:none;">fleaber.pt</a><br>
            Precisas de ajuda? <a href="mailto:geral@fleaber.pt" style="color:#007782;text-decoration:none;">geral@fleaber.pt</a>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function lineRowsHtml(lines: OrderLineEmail[]): string {
  if (!lines.length) return "";
  return lines.map((line) => {
    const img = sanitizeImageUrl(line.imageUrl);
    const qty = line.qty && line.qty > 1 ? ` ×${line.qty}` : "";
    const price = (line.priceLabel ?? "").trim();
    const thumb = img
      ? `<td width="72" valign="top" style="padding:0 12px 0 0;">
            <img src="${esc(img)}" alt="" width="72" height="72" style="display:block;width:72px;height:72px;object-fit:cover;border-radius:12px;border:1px solid #E8EEF0;">
          </td>`
      : "";
    return `<tr>
        ${thumb}
        <td valign="top" style="padding:0 0 14px 0;">
          <p style="margin:0 0 4px;font-size:16px;font-weight:700;color:#101518;line-height:1.35;">${esc(line.title)}${esc(qty)}</p>
          ${price ? `<p style="margin:0;font-size:14px;color:#57636C;">${esc(price)}</p>` : ""}
        </td>
      </tr>`;
  }).join("");
}

function orderCardHtml(opts: {
  ref: string;
  /** Chip opcional — E1/E2 sem «Pago»/«Venda paga». */
  statusLabel?: string | null;
  showStatusChip?: boolean;
  lines: OrderLineEmail[];
  breakdown?: {
    items?: string | null;
    shipping?: string | null;
    protection?: string | null;
    total?: string | null;
    totalCaption?: string | null;
  };
}): string {
  const status = (opts.statusLabel ?? "").trim();
  const showChip = opts.showStatusChip === true && !!status;
  const bd = opts.breakdown ?? {};
  const totalCaption = (bd.totalCaption ?? "Total pago").trim() || "Total pago";
  const hasBd = !!(bd.items || bd.shipping || bd.protection || bd.total);
  let breakdownHtml = "";
  if (hasBd) {
    const rows: string[] = [];
    if (bd.items) {
      rows.push(
        `<tr><td style="padding:4px 0;font-size:14px;color:#57636C;">Artigos</td><td align="right" style="padding:4px 0;font-size:14px;color:#101518;">${esc(bd.items)}</td></tr>`,
      );
    }
    if (bd.shipping) {
      rows.push(
        `<tr><td style="padding:4px 0;font-size:14px;color:#57636C;">Portes</td><td align="right" style="padding:4px 0;font-size:14px;color:#101518;">${esc(bd.shipping)}</td></tr>`,
      );
    }
    if (bd.protection) {
      rows.push(
        `<tr><td style="padding:4px 0;font-size:14px;color:#57636C;">Proteção Fleaber</td><td align="right" style="padding:4px 0;font-size:14px;color:#101518;">${esc(bd.protection)}</td></tr>`,
      );
    }
    if (bd.total) {
      rows.push(
        `<tr><td style="padding:10px 0 0;font-size:16px;font-weight:700;color:#101518;border-top:1px solid #E8EEF0;">${esc(totalCaption)}</td><td align="right" style="padding:10px 0 0;font-size:16px;font-weight:700;color:#007782;border-top:1px solid #E8EEF0;">${esc(bd.total)}</td></tr>`,
      );
    }
    breakdownHtml =
      `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:8px;">${rows.join("")}</table>`;
  }

  return `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 20px;background:#F4F7F8;border-radius:16px;overflow:hidden;">
    <tr>
      <td style="padding:16px 18px 12px;">
        <p style="margin:0 0 ${showChip ? "8" : "12"}px;font-size:14px;color:#57636C;">Referência <strong style="color:#101518;">${esc(opts.ref)}</strong></p>
        ${showChip ? `<p style="margin:0 0 12px;display:inline-block;background:#007782;color:#ffffff;font-size:12px;font-weight:700;letter-spacing:0.4px;padding:4px 10px;border-radius:999px;">${esc(status)}</p>` : ""}
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          ${lineRowsHtml(opts.lines)}
        </table>
        ${breakdownHtml}
      </td>
    </tr>
  </table>`;
}

function resolveLines(ctx: OrderEmailContext): OrderLineEmail[] {
  if (ctx.lines && ctx.lines.length) {
    return ctx.lines.map((l) => ({
      ...l,
      imageUrl: sanitizeImageUrl(l.imageUrl),
    }));
  }
  const title = (ctx.productTitle ?? "").trim();
  if (!title) return [];
  return [{
    title,
    priceLabel: ctx.itemsTotalLabel ?? ctx.totalLabel ?? null,
    qty: 1,
    imageUrl: null,
  }];
}

export function buildCommercialEmail(
  kind: string,
  ctx: OrderEmailContext = {},
): { subject: string; html: string; text: string; ctaUrl: string } | null {
  if (!wantsCommercialEmail(kind)) return null;

  const k = kind.trim().toLowerCase() as CommercialEmailKind;

  // ZIP 149 / 152.1 — emails de conjunto pré-pagamento (sem orderId).
  if (isBundleQuoteEmailKind(k)) {
    const ctaUrl = bundleMensagensDeepLink(ctx.chatId);
    const subject = commercialSubject(k, ctx);
    const prazoNatural = (ctx.payDeadlineLabel ?? "").trim();
    const confirmNatural = (ctx.confirmDeadlineLabel ?? "").trim();
    const total = (ctx.grandTotalLabel ?? ctx.totalLabel ?? "").trim();
    const arts = (ctx.articlesTotalLabel ?? ctx.itemsTotalLabel ?? "").trim();
    const ship = (ctx.shippingLabel ?? "").trim();
    const prot = (ctx.protectionLabel ?? "").trim();
    const lines = resolveLines(ctx);
    const articlesCard = lines.length
      ? orderCardHtml({
        ref: shortRef(ctx.bundleId) || "conjunto",
        showStatusChip: false,
        lines,
        breakdown: (arts || ship || prot || total)
          ? {
            items: arts || null,
            shipping: ship || null,
            protection: prot || null,
            total: total || null,
            totalCaption: "Total",
          }
          : undefined,
      })
      : (arts || ship || prot || total
        ? `<p style="margin:0 0 16px;font-size:14px;color:#101518;">` +
          (arts ? `Artigos: <strong>${esc(arts)}</strong><br/>` : "") +
          (ship ? `Portes: <strong>${esc(ship)}</strong><br/>` : "") +
          (prot ? `Proteção Fleaber: <strong>${esc(prot)}</strong><br/>` : "") +
          (total ? `Total: <strong>${esc(total)}</strong>` : "") +
          `</p>`
        : "");
    const linesText = lines.map((l) => {
      const qty = l.qty && l.qty > 1 ? ` ×${l.qty}` : "";
      const price = (l.priceLabel ?? "").trim();
      return `- ${l.title}${qty}${price ? ` · ${price}` : ""}`;
    }).join("\n");

    if (k === "bundle_proposal" || k === "bundle_purchase_request") {
      // Uma frase: 48h + prazo dinâmico (sem repetir «Tens…» / «Tens 48 horas»).
      const prazoConfirm = confirmNatural
        ? `Tens 48 horas para confirmar os portes, até ${confirmNatural}.`
        : "Tens 48 horas para confirmar os portes.";
      const inner =
        `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">Recebeste um <strong>pedido de conjunto</strong> na Fleaber. Confirma o peso e os portes para que a compra possa ser concluída.</p>` +
        articlesCard +
        `<p style="margin:0 0 16px;"><strong>${esc(prazoConfirm)}</strong> Até lá, os artigos <strong>continuam disponíveis</strong> para outras pessoas — não há reserva nem cobrança.</p>`;
      const html = shell({
        headline: "Novo pedido de conjunto",
        preheader: "Confirma os portes em 48 horas",
        innerHtml: inner,
        ctaLabel: "Abrir conversa do conjunto",
        ctaUrl,
      });
      const text = [
        "Olá,",
        "",
        "Recebeste um pedido de conjunto na Fleaber.",
        "Confirma o peso e os portes para que a compra possa ser concluída.",
        linesText || null,
        prazoConfirm,
        "Os artigos continuam disponíveis — sem reserva nem cobrança.",
        "",
        `Abrir conversa: ${ctaUrl}`,
      ].filter((x) => x != null && String(x).length).join("\n");
      return { subject, html, text, ctaUrl };
    }
    if (k === "bundle_quote_ready") {
      const prazoPay = prazoNatural
        ? `Tens 48 horas (até ${prazoNatural}) para concluir a compra ou podes desistir livremente.`
        : "Tens 48 horas para concluir a compra ou podes desistir livremente.";
      const inner =
        `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">Os portes do teu conjunto já foram confirmados. Já podes pagar — <strong>os artigos não ficaram reservados</strong> até ao pagamento.</p>` +
        articlesCard +
        `<p style="margin:0 0 16px;">${esc(prazoPay)}</p>`;
      const html = shell({
        headline: "Portes confirmados",
        preheader: "Já podes pagar o conjunto — 48 horas",
        innerHtml: inner,
        ctaLabel: "Abrir conversa para pagar",
        ctaUrl,
      });
      const text = [
        "Olá,",
        "",
        "Os portes do teu conjunto já foram confirmados. Já podes pagar.",
        "Os artigos não ficam reservados até ao pagamento.",
        linesText || null,
        arts ? `Artigos: ${arts}` : null,
        ship ? `Portes: ${ship}` : null,
        prot ? `Proteção Fleaber: ${prot}` : null,
        total ? `Total: ${total}` : null,
        prazoPay,
        "",
        `Abrir conversa: ${ctaUrl}`,
      ].filter((x) => x != null && String(x).length).join("\n");
      return { subject, html, text, ctaUrl };
    }
    if (k === "bundle_expired") {
      const reason = (ctx.expireReason ?? "").toLowerCase();
      const payTimeout =
        reason.includes("buyer_pay") || reason.includes("pay_timeout");
      const sellerTimeout =
        reason.includes("seller_confirm") || reason.includes("confirm_timeout");
      const why = payTimeout
        ? "O prazo para pagar terminou (48 horas após a confirmação dos portes)."
        : sellerTimeout
        ? "O pedido expirou porque os portes não foram confirmados no prazo de 48 horas."
        : "O pedido de conjunto expirou (prazo de 48 horas).";
      const headline = payTimeout
        ? "O prazo para pagar terminou"
        : "Pedido de conjunto expirado";
      const inner =
        `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">${esc(why)} <strong>Não foi efetuada qualquer cobrança</strong> e os artigos não estavam reservados.</p>` +
        articlesCard +
        `<p style="margin:0 0 16px;">Podes pedir um novo conjunto quando quiseres.</p>`;
      const html = shell({
        headline,
        preheader: "Sem cobrança — artigos não estavam reservados",
        innerHtml: inner,
        ctaLabel: "Abrir conversa do conjunto",
        ctaUrl,
      });
      const text = [
        "Olá,",
        "",
        why,
        "Não foi efetuada qualquer cobrança. Os artigos não estavam reservados.",
        linesText || null,
        "",
        `Abrir conversa: ${ctaUrl}`,
      ].filter((x) => x != null && String(x).length).join("\n");
      return { subject, html, text, ctaUrl };
    }
    // bundle_quote_invalidated
    const inner =
      `<p style="margin:0 0 16px;">Olá,</p>` +
      `<p style="margin:0 0 16px;"><strong>O teu conjunto já não está disponível</strong> nas condições anteriores (um artigo foi vendido ou o preço mudou).</p>` +
      articlesCard +
      `<p style="margin:0 0 16px;">É necessário confirmar novamente a disponibilidade e o preço dos artigos. Não foi efetuada qualquer cobrança.</p>`;
    const html = shell({
      headline: "O teu conjunto já não está disponível",
      preheader: "Disponibilidade ou preço alterados — sem cobrança",
      innerHtml: inner,
      ctaLabel: "Abrir conversa do conjunto",
      ctaUrl,
    });
    const text = [
      "Olá,",
      "",
      "O teu conjunto já não está disponível nas condições anteriores.",
      "É necessário confirmar novamente a disponibilidade e o preço dos artigos.",
      "Não foi efetuada qualquer cobrança.",
      linesText || null,
      "",
      `Abrir conversa: ${ctaUrl}`,
    ].filter((x) => x != null && String(x).length).join("\n");
    return { subject, html, text, ctaUrl };
  }

  const orderId = (ctx.orderId ?? "").trim();
  // Sem encomenda real → não construir HTML com link genérico/incorrecto.
  const deep = orderDeepLinkUrl(orderId);
  if (!deep) return null;
  // Só aceita ctaUrl externo se já incluir este orderId (nunca a lista).
  const provided = (ctx.ctaUrl ?? "").trim();
  const ctaUrl =
    provided &&
      (provided.includes(`orderId=${orderId}`) ||
        provided.includes(`orderId=${encodeURIComponent(orderId)}`))
      ? provided
      : deep;
  const ref = (ctx.referenceLabel?.trim() || shortRef(orderId)).trim();
  const handed = ctx.handedToCarrier === true;
  const subject = commercialSubject(k, { ...ctx, handedToCarrier: handed });
  const lines = resolveLines(ctx);
  const articleCount = lines.reduce((n, l) => n + Math.max(1, l.qty ?? 1), 0);

  if (k === "order_paid_buyer") {
    const card = orderCardHtml({
      ref,
      showStatusChip: false,
      lines,
      breakdown: {
        items: ctx.itemsTotalLabel,
        shipping: ctx.shippingLabel,
        protection: ctx.protectionLabel ??
          (ctx.hasBuyerProtection === false ? null : null),
        total: ctx.totalLabel,
        totalCaption: "Total pago",
      },
    });
    // Se há Proteção mas sem valor discriminado, linha textual
    const protNote = ctx.hasBuyerProtection !== false && !ctx.protectionLabel
      ? `<p style="margin:0 0 16px;font-size:14px;color:#57636C;">Esta compra inclui <strong style="color:#101518;">Proteção Fleaber</strong>.</p>`
      : "";
    const inner =
      `<p style="margin:0 0 16px;">Olá,</p>` +
      `<p style="margin:0 0 16px;">Boa notícia — o pagamento da tua compra na <strong>Fleaber</strong> foi confirmado. Já podes acompanhar tudo na tua área de encomendas.</p>` +
      card +
      protNote +
      `<p style="margin:0 0 16px;">Se quiseres, fala com o vendedor diretamente na Fleaber.</p>` +
      `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">Se não foste tu a fazer esta compra, contacta-nos: <a href="mailto:geral@fleaber.pt" style="color:#007782;">geral@fleaber.pt</a></p>`;
    const html = shell({
      headline: "Compra confirmada",
      preheader: `Pagamento confirmado · ${ref}`,
      innerHtml: inner,
      ctaLabel: "Ver a minha encomenda",
      ctaUrl,
    });
    const textLines = [
      "Olá,",
      "",
      "Boa notícia — o pagamento da tua compra na Fleaber foi confirmado.",
      `Referência: ${ref}`,
      ...lines.map((l) =>
        `- ${l.title}${l.priceLabel ? ` · ${l.priceLabel}` : ""}`
      ),
      ctx.itemsTotalLabel ? `Artigos: ${ctx.itemsTotalLabel}` : null,
      ctx.shippingLabel ? `Portes: ${ctx.shippingLabel}` : null,
      ctx.protectionLabel ? `Proteção Fleaber: ${ctx.protectionLabel}` : null,
      ctx.totalLabel ? `Total pago: ${ctx.totalLabel}` : null,
      "",
      `Ver a minha encomenda: ${ctaUrl}`,
      "",
      "Se não foste tu: geral@fleaber.pt",
      "Equipa Fleaber",
    ];
    return {
      subject,
      html,
      text: textLines.filter((l) => l != null).join("\n"),
      ctaUrl,
    };
  }

  if (k === "order_paid_seller") {
    const plural = articleCount > 1;
    // Valor da venda = artigos (sem taxa de protecção do comprador).
    const saleLabel = (ctx.itemsTotalLabel ?? ctx.totalLabel)?.trim() || null;
    const card = orderCardHtml({
      ref,
      showStatusChip: false,
      lines,
      breakdown: {
        total: saleLabel,
        totalCaption: "Valor da venda",
      },
    });
    const step1 = plural
      ? "1. Prepara os artigos com cuidado"
      : "1. Prepara o artigo com cuidado";
    const step3 = plural
      ? "3. Entrega os artigos à transportadora e marca o envio"
      : "3. Entrega o artigo à transportadora e marca o envio";
    const steps =
      `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 16px;">
        <tr><td style="padding:12px 14px;background:#F4F7F8;border-radius:14px;">
          <p style="margin:0 0 10px;font-size:16px;font-weight:700;color:#101518;">Próximos passos</p>
          <p style="margin:0 0 8px;font-size:16px;color:#101518;">${esc(step1)}</p>
          <p style="margin:0 0 8px;font-size:16px;color:#101518;">2. Organiza o envio na Fleaber</p>
          <p style="margin:0;font-size:16px;color:#101518;">${esc(step3)}</p>
        </td></tr>
      </table>`;
    // Ajuda só no rodapé do shell (evitar duplicar «Precisas de ajuda?»).
    const inner =
      `<p style="margin:0 0 16px;">Olá,</p>` +
      `<p style="margin:0 0 16px;">Parabéns — o pagamento desta venda já está confirmado.</p>` +
      card +
      steps;
    const html = shell({
      headline: "Parabéns pela tua venda!",
      preheader: `Nova venda · ${ref}`,
      innerHtml: inner,
      ctaLabel: "Gerir a minha venda",
      ctaUrl,
    });
    const text = [
      "Olá,",
      "",
      "Parabéns — o pagamento desta venda já está confirmado.",
      `Referência: ${ref}`,
      ...lines.map((l) =>
        `- ${l.title}${l.priceLabel ? ` · ${l.priceLabel}` : ""}`
      ),
      saleLabel ? `Valor da venda: ${saleLabel}` : null,
      "",
      "Próximos passos:",
      step1,
      "2. Organiza o envio na Fleaber",
      step3,
      "",
      `Gerir a minha venda: ${ctaUrl}`,
      "",
      "Equipa Fleaber",
    ].filter((l) => l != null).join("\n");
    return { subject, html, text, ctaUrl };
  }

  if (k === "reservation_order_shipped") {
    // E3 — sem CTA duplicado para tracking (link no cartão se existir)
    const trackingCode = (ctx.trackingCode ?? "").trim();
    const trackingUrl = (ctx.trackingUrl ?? "").trim();
    const carrier = (ctx.carrierLabel ?? "").trim();

    let leadHtml: string;
    let leadText: string;
    let statusChip: string;
    if (handed) {
      leadHtml =
        `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">Boa notícia — a tua encomenda <strong>está a caminho</strong>. A transportadora já a recebeu.</p>`;
      leadText =
        "Boa notícia — a tua encomenda está a caminho. A transportadora já a recebeu.";
      statusChip = "A caminho";
    } else {
      leadHtml =
        `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">O vendedor confirmou o envio da tua encomenda na Fleaber. Quando a transportadora receber a encomenda, o estado passa a «a caminho».</p>`;
      leadText =
        "O vendedor confirmou o envio da tua encomenda na Fleaber. Quando a transportadora receber a encomenda, o estado passa a «a caminho».";
      statusChip = "Envio confirmado";
    }

    const shipRows: string[] = [
      `<tr><td style="padding:4px 0;font-size:14px;color:#57636C;">Estado</td><td align="right" style="padding:4px 0;font-size:14px;font-weight:700;color:#101518;">${esc(statusChip)}</td></tr>`,
    ];
    if (carrier) {
      shipRows.push(
        `<tr><td style="padding:4px 0;font-size:14px;color:#57636C;">Transportadora</td><td align="right" style="padding:4px 0;font-size:14px;color:#101518;">${esc(carrier)}</td></tr>`,
      );
    }
    if (trackingCode) {
      shipRows.push(
        `<tr><td style="padding:4px 0;font-size:14px;color:#57636C;">Código de seguimento</td><td align="right" style="padding:4px 0;font-size:14px;color:#101518;">${esc(trackingCode)}</td></tr>`,
      );
    } else {
      shipRows.push(
        `<tr><td colspan="2" style="padding:8px 0 0;font-size:14px;color:#57636C;">Quando houver código de seguimento, também o vês na Fleaber.</td></tr>`,
      );
    }

    const shipCard =
      `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 20px;background:#F4F7F8;border-radius:16px;">
      <tr><td style="padding:16px 18px;">
        <p style="margin:0 0 12px;font-size:14px;color:#57636C;">Referência <strong style="color:#101518;">${esc(ref)}</strong></p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">${lineRowsHtml(lines)}</table>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:8px;">${shipRows.join("")}</table>
      </td></tr>
    </table>`;

    const receiveHint = articleCount > 1
      ? "Quando receberes os artigos, confirma a receção na Fleaber."
      : "Quando receberes o artigo, confirma a receção na Fleaber.";

    const inner =
      leadHtml +
      shipCard +
      `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">${esc(receiveHint)}</p>`;

    const html = shell({
      headline: handed ? "A tua encomenda está a caminho" : "Envio confirmado",
      preheader: handed ? `A caminho · ${ref}` : `Envio confirmado · ${ref}`,
      innerHtml: inner,
      ctaLabel: "Acompanhar encomenda",
      ctaUrl,
    });

    const text = [
      "Olá,",
      "",
      leadText,
      `Referência: ${ref}`,
      ...lines.map((l) => `- ${l.title}`),
      `Estado: ${statusChip}`,
      carrier ? `Transportadora: ${carrier}` : null,
      trackingCode ? `Código de seguimento: ${trackingCode}` : null,
      trackingUrl && trackingCode ? `Seguimento: ${trackingUrl}` : null,
      "",
      `Acompanhar encomenda: ${ctaUrl}`,
      "",
      receiveHint,
      "Equipa Fleaber",
    ].filter((l) => l != null).join("\n");

    return { subject, html, text, ctaUrl };
  }

  // —— ZIP 142: diferença de portes / prazos ——
  const chargeCents = ctx.amountChargeCents ?? ctx.shippingDeltaCents ??
    ctx.deltaCents ?? null;
  const chargeLabel = formatCents(chargeCents);
  const deltaLabel = formatCents(
    ctx.shippingDeltaCents ?? ctx.deltaCents ?? chargeCents,
  );
  const bandFrom = weightBandLabel(ctx.weightBandFrom);
  const bandTo = weightBandLabel(ctx.weightBandTo);
  const payUntil = formatDeadlinePt(ctx.payDeadlineAt);
  const shipBy = formatDeadlinePt(ctx.shipByAt);
  const refund = (ctx.refundHint ?? "").trim() || DEFAULT_REFUND_HINT;
  const role = ctx.audienceRole === "seller" ? "seller" : "buyer";

  if (k === "shipping_delta_requested") {
    const card = orderCardHtml({
      ref,
      showStatusChip: false,
      lines,
      breakdown: {
        shipping: deltaLabel,
        total: chargeLabel,
        totalCaption: "Total a pagar (só portes)",
      },
    });
    const inner =
      `<p style="margin:0 0 16px;">Olá,</p>` +
      `<p style="margin:0 0 16px;">O vendedor atualizou o peso desta encomenda (<strong>${esc(bandFrom)}</strong> → <strong>${esc(bandTo)}</strong>). Para o envio avançar, falta pagar a <strong>diferença de portes</strong>.</p>` +
      `<p style="margin:0 0 16px;font-size:14px;color:#57636C;">Isto <strong>não</strong> é uma nova compra e <strong>não</strong> inclui Proteção Fleaber adicional.</p>` +
      card +
      (payUntil
        ? `<p style="margin:0 0 16px;">Tens até <strong>${esc(payUntil)}</strong> para pagar. Se não o fizeres a tempo, a encomenda pode ser cancelada com reembolso integral.</p>`
        : `<p style="margin:0 0 16px;">Paga a diferença na Fleaber o mais cedo possível para o vendedor poder enviar.</p>`) +
      `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">Abre a encomenda para concluir o pagamento com segurança.</p>`;
    const html = shell({
      headline: "Diferença de portes a pagar",
      preheader: `Diferença de portes · ${ref}`,
      innerHtml: inner,
      ctaLabel: "Ver a minha encomenda",
      ctaUrl,
    });
    const text = [
      "Olá,",
      "",
      `O vendedor atualizou o peso desta encomenda (${bandFrom} → ${bandTo}).`,
      "Isto não é uma nova compra e não inclui Proteção Fleaber adicional.",
      `Referência: ${ref}`,
      ...lines.map((l) => `- ${l.title}`),
      deltaLabel ? `Diferença de portes: ${deltaLabel}` : null,
      chargeLabel ? `Total a pagar (só portes): ${chargeLabel}` : null,
      payUntil ? `Pagar até: ${payUntil}` : null,
      "",
      `Ver a minha encomenda: ${ctaUrl}`,
      "",
      "Equipa Fleaber",
    ].filter((l) => l != null).join("\n");
    return { subject, html, text, ctaUrl };
  }

  if (k === "shipping_delta_paid") {
    const isSeller = role === "seller";
    const card = orderCardHtml({
      ref,
      showStatusChip: false,
      lines,
      breakdown: {
        total: chargeLabel ?? deltaLabel,
        totalCaption: "Diferença de portes paga",
      },
    });
    const lead = isSeller
      ? `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">Boa notícia — o comprador pagou a <strong>diferença de portes</strong>. Podes preparar o envio com tranquilidade.</p>` +
        `<p style="margin:0 0 16px;font-size:14px;color:#57636C;">Isto <strong>não</strong> é uma nova venda: é só o ajuste dos portes desta encomenda.</p>`
      : `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">Confirmámos o pagamento da <strong>diferença de portes</strong>. O vendedor já pode enviar a tua encomenda.</p>` +
        `<p style="margin:0 0 16px;font-size:14px;color:#57636C;">Isto <strong>não</strong> é uma nova compra e <strong>não</strong> inclui Proteção Fleaber adicional.</p>`;
    const inner = lead + card +
      (shipBy
        ? `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">Prazo de envio estimado: <strong>${esc(shipBy)}</strong>.</p>`
        : `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">Acompanha o estado na Fleaber.</p>`);
    const html = shell({
      headline: isSeller
        ? "Diferença de portes paga"
        : "Diferença de portes confirmada",
      preheader: `Portes confirmados · ${ref}`,
      innerHtml: inner,
      ctaLabel: isSeller ? "Gerir a minha venda" : "Ver a minha encomenda",
      ctaUrl,
    });
    const text = [
      "Olá,",
      "",
      isSeller
        ? "O comprador pagou a diferença de portes. Podes preparar o envio."
        : "Confirmámos o pagamento da diferença de portes.",
      "Isto não é uma nova compra/venda.",
      `Referência: ${ref}`,
      ...lines.map((l) => `- ${l.title}`),
      (chargeLabel ?? deltaLabel)
        ? `Diferença de portes: ${chargeLabel ?? deltaLabel}`
        : null,
      shipBy ? `Prazo de envio: ${shipBy}` : null,
      "",
      `${isSeller ? "Gerir a minha venda" : "Ver a minha encomenda"}: ${ctaUrl}`,
      "",
      "Equipa Fleaber",
    ].filter((l) => l != null).join("\n");
    return { subject, html, text, ctaUrl };
  }

  if (k === "shipping_delta_expired_cancelled") {
    const isSeller = role === "seller";
    const rf = refundStatusCopy({
      refundStatus: ctx.refundStatus,
      refundHint: refund,
    });
    const card = orderCardHtml({
      ref,
      showStatusChip: false,
      lines,
    });
    const lead = isSeller
      ? `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">A encomenda foi <strong>cancelada</strong> porque a diferença de portes não foi paga a tempo.</p>` +
        `<p style="margin:0 0 8px;"><strong>${esc(rf.title)}</strong></p>` +
        `<p style="margin:0 0 16px;">${esc(rf.body)}</p>`
      : `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">A tua encomenda foi <strong>cancelada</strong> porque a diferença de portes não foi paga dentro do prazo.</p>` +
        `<p style="margin:0 0 8px;"><strong>${esc(rf.title)}</strong></p>` +
        `<p style="margin:0 0 16px;">${esc(rf.body)}</p>`;
    const inner = lead + card +
      `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">Se tiveres dúvidas, fala connosco em geral@fleaber.pt.</p>`;
    const html = shell({
      headline: "Encomenda cancelada",
      preheader: `Cancelada · portes · ${ref}`,
      innerHtml: inner,
      ctaLabel: isSeller ? "Ver a encomenda" : "Ver a minha encomenda",
      ctaUrl,
    });
    const text = [
      "Olá,",
      "",
      isSeller
        ? "A encomenda foi cancelada porque a diferença de portes não foi paga a tempo."
        : "A tua encomenda foi cancelada porque a diferença de portes não foi paga a tempo.",
      `${rf.title}: ${rf.body}`,
      `Referência: ${ref}`,
      ...lines.map((l) => `- ${l.title}`),
      "",
      `Ver a encomenda: ${ctaUrl}`,
      "",
      "Equipa Fleaber",
    ].join("\n");
    return { subject, html, text, ctaUrl };
  }

  if (k === "ship_deadline_auto_cancelled") {
    const isSeller = role === "seller";
    const rf = refundStatusCopy({
      refundStatus: ctx.refundStatus,
      refundHint: refund,
    });
    const card = orderCardHtml({
      ref,
      showStatusChip: false,
      lines,
    });
    const lead = isSeller
      ? `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">A encomenda foi <strong>cancelada</strong> porque o prazo de envio foi ultrapassado${shipBy ? ` (${esc(shipBy)})` : ""}.</p>` +
        `<p style="margin:0 0 8px;"><strong>${esc(rf.title)}</strong></p>` +
        `<p style="margin:0 0 16px;">${esc(rf.body)}</p>`
      : `<p style="margin:0 0 16px;">Olá,</p>` +
        `<p style="margin:0 0 16px;">A tua encomenda foi <strong>cancelada</strong> porque o prazo de envio foi ultrapassado${shipBy ? ` (${esc(shipBy)})` : ""}.</p>` +
        `<p style="margin:0 0 8px;"><strong>${esc(rf.title)}</strong></p>` +
        `<p style="margin:0 0 16px;">${esc(rf.body)}</p>`;
    const inner = lead + card +
      `<p style="margin:0 0 8px;color:#57636C;font-size:14px;">Lamentamos o transtorno. Se precisares de ajuda: geral@fleaber.pt.</p>`;
    const html = shell({
      headline: "Encomenda cancelada",
      preheader: `Cancelada · prazo envio · ${ref}`,
      innerHtml: inner,
      ctaLabel: isSeller ? "Ver a encomenda" : "Ver a minha encomenda",
      ctaUrl,
    });
    const text = [
      "Olá,",
      "",
      isSeller
        ? `A encomenda foi cancelada porque o prazo de envio foi ultrapassado${shipBy ? ` (${shipBy})` : ""}.`
        : `A tua encomenda foi cancelada porque o prazo de envio foi ultrapassado${shipBy ? ` (${shipBy})` : ""}.`,
      `${rf.title}: ${rf.body}`,
      `Referência: ${ref}`,
      ...lines.map((l) => `- ${l.title}`),
      "",
      `Ver a encomenda: ${ctaUrl}`,
      "",
      "Equipa Fleaber",
    ].join("\n");
    return { subject, html, text, ctaUrl };
  }

  return null;
}
