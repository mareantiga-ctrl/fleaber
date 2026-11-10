import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  audienceRoleFromDedupe,
  buildCommercialEmail,
  canSendShippedEmail,
  DEFAULT_REFUND_HINT,
  formatDeadlinePt,
  HUB_ENCOMENDAS_URL,
  isOrderUuid,
  orderDeepLinkUrl,
  parseOrderIdFromDedupe,
  refundStatusCopy,
  resolveCommercialOrderId,
  wantsCommercialEmail,
  commercialSubject,
  sanitizeImageUrl,
} from "./email_commercial.ts";

const OID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const DEEP = orderDeepLinkUrl(OID)!;

Deno.test("wantsCommercialEmail allowlist E1-E3 + delta 142", () => {
  assertEquals(wantsCommercialEmail("order_paid_buyer"), true);
  assertEquals(wantsCommercialEmail("shipping_delta_requested"), true);
  assertEquals(wantsCommercialEmail("shipping_delta_paid"), true);
  assertEquals(wantsCommercialEmail("shipping_delta_expired_cancelled"), true);
  assertEquals(wantsCommercialEmail("ship_deadline_auto_cancelled"), true);
  assertEquals(wantsCommercialEmail("seguro_fleaber_paid"), false);
  assertEquals(wantsCommercialEmail("bundle_quote_ready"), true);
  assertEquals(wantsCommercialEmail("bundle_expired"), true);
  assertEquals(wantsCommercialEmail("bundle_quote_invalidated"), true);
});

Deno.test("bundle_quote_ready email sem orderId", () => {
  const built = buildCommercialEmail("bundle_quote_ready", {
    chatId: OID,
    grandTotalLabel: "12,71 €",
    articlesTotalLabel: "9,00 €",
    shippingLabel: "2,99 €",
    protectionLabel: "0,72 €",
    payDeadlineLabel: "06/11/2026 15:30",
  });
  assert(built != null);
  assertEquals(built!.subject.includes("Portes confirmados"), true);
  assert(built!.text.includes("não ficam reservados") || built!.text.includes("não ficaram reservados"));
  assert(built!.html.includes("Abrir mensagens") || built!.ctaUrl.includes("listaConversas"));
});

Deno.test("subjects aprovados", () => {
  assertEquals(
    commercialSubject("order_paid_buyer"),
    "Já está! A tua compra na Fleaber foi confirmada",
  );
  assertEquals(
    commercialSubject("order_paid_seller"),
    "🎉 Parabéns! Fizeste uma venda na Fleaber!",
  );
  assertEquals(
    commercialSubject("reservation_order_shipped"),
    "O envio da tua encomenda foi confirmado",
  );
  assertEquals(
    commercialSubject("reservation_order_shipped", { handedToCarrier: true }),
    "A tua encomenda está a caminho",
  );
});

Deno.test("sanitizeImageUrl rejeita inventados", () => {
  assertEquals(sanitizeImageUrl(""), null);
  assertEquals(sanitizeImageUrl("data:image/png;base64,xx"), null);
  assertEquals(sanitizeImageUrl("/local/x.jpg"), null);
  assertEquals(
    sanitizeImageUrl("https://cdn.example/fleaber/produto.jpg"),
    "https://cdn.example/fleaber/produto.jpg",
  );
});

Deno.test("parseOrderIdFromDedupe + resolve", () => {
  assertEquals(parseOrderIdFromDedupe(`order_paid:${OID}:buyer`), OID);
  assertEquals(parseOrderIdFromDedupe(`shipped:${OID}`), OID);
  assertEquals(parseOrderIdFromDedupe("order_paid::buyer"), null);
  assertEquals(parseOrderIdFromDedupe(""), null);
  assertEquals(resolveCommercialOrderId({ dedupe: `shipped:${OID}` }), OID);
  assertEquals(resolveCommercialOrderId({ orderId: OID }), OID);
  assertEquals(resolveCommercialOrderId({ dedupe: "nope" }), null);
  assertEquals(isOrderUuid(OID), true);
  assertEquals(isOrderUuid("not-a-uuid"), false);
});

Deno.test("orderDeepLinkUrl exige UUID — nunca lista genérica", () => {
  assertEquals(
    DEEP,
    `https://fleaber.pt/fleahub/#/perfil?secao=encomendas&orderId=${OID}`,
  );
  assertEquals(orderDeepLinkUrl(""), null);
  assertEquals(orderDeepLinkUrl(null), null);
  assertEquals(orderDeepLinkUrl("lista"), null);
  assert(DEEP !== HUB_ENCOMENDAS_URL);
});

Deno.test("sem orderId → não constrói email comercial", () => {
  assertEquals(
    buildCommercialEmail("order_paid_buyer", {
      totalLabel: "10,00 €",
      lines: [{ title: "X" }],
    }),
    null,
  );
  assertEquals(
    buildCommercialEmail("order_paid_seller", { orderId: "x" }),
    null,
  );
});

Deno.test("E1 cartão multi-artigo + breakdown + foto + deep link + PT", () => {
  const img =
    "https://bpmpkzwnrbmuqnhgdscf.supabase.co/storage/v1/object/public/product-images/demo.jpg";
  const e = buildCommercialEmail("order_paid_buyer", {
    orderId: OID,
    statusLabel: "Pago",
    itemsTotalLabel: "25,00 €",
    shippingLabel: "3,50 €",
    protectionLabel: "2,08 €",
    totalLabel: "30,58 €",
    hasBuyerProtection: true,
    lines: [
      {
        title: "Casaco de ganga vintage M",
        priceLabel: "18,00 €",
        qty: 1,
        imageUrl: img,
      },
      {
        title: "Cachecol lã",
        priceLabel: "7,00 €",
        qty: 1,
        imageUrl: img,
      },
    ],
  });
  assert(e != null);
  assert(e!.html.includes(img));
  assert(e!.html.includes("Casaco de ganga"));
  assert(e!.html.includes("Cachecol"));
  assert(e!.html.includes("Portes"));
  assert(e!.html.includes("Proteção Fleaber"));
  assert(e!.html.includes("Total pago"));
  assert(e!.html.includes("diretamente"));
  assert(!e!.html.includes("directamente"));
  assert(!e!.html.includes("Email transaccional"));
  assert(!e!.html.includes("placeholder"));
  assert(!e!.html.includes("border-radius:999px"));
  assert(!e!.html.includes(">Pago</"));
  assertEquals(e!.ctaUrl, DEEP);
  assert(e!.html.includes(`orderId=${OID}`));
  assert(!e!.ctaUrl.endsWith("secao=encomendas"));
  // ctaUrl genérico é ignorado
  const ignored = buildCommercialEmail("order_paid_buyer", {
    orderId: OID,
    totalLabel: "1,00 €",
    lines: [{ title: "X" }],
    ctaUrl: HUB_ENCOMENDAS_URL,
  });
  assertEquals(ignored!.ctaUrl, DEEP);
});

Deno.test("E1 sem URL de imagem não inventa foto", () => {
  const e = buildCommercialEmail("order_paid_buyer", {
    orderId: OID,
    totalLabel: "10,00 €",
    lines: [{ title: "Artigo sem foto", priceLabel: "10,00 €" }],
  });
  assert(e != null);
  assert(!e!.html.includes("<img"));
});

Deno.test("E2 Valor da venda + plural + deep link", () => {
  const single = buildCommercialEmail("order_paid_seller", {
    orderId: OID,
    itemsTotalLabel: "18,00 €",
    totalLabel: "20,50 €",
    statusLabel: "Venda paga",
    lines: [{ title: "Vestido", priceLabel: "18,00 €" }],
  });
  assert(single != null);
  assert(single!.html.includes("Valor da venda"));
  assert(single!.html.includes("18,00 €"));
  assert(!single!.html.includes("Total pago"));
  assert(single!.html.includes("Prepara o artigo com cuidado"));
  assert(single!.html.includes("Entrega o artigo à transportadora"));
  assert(!single!.html.includes("Venda paga"));
  assert(!single!.html.includes("border-radius:999px"));
  assertEquals(single!.ctaUrl, DEEP);
  // Ajuda só 1× (rodapé do shell)
  const helpHits = (single!.html.match(/Precisas de ajuda\?/g) ?? []).length;
  assertEquals(helpHits, 1);

  const multi = buildCommercialEmail("order_paid_seller", {
    orderId: OID,
    itemsTotalLabel: "25,00 €",
    lines: [
      { title: "A", priceLabel: "10,00 €", qty: 1 },
      { title: "B", priceLabel: "15,00 €", qty: 1 },
    ],
  });
  assert(multi!.html.includes("Prepara os artigos com cuidado"));
  assert(multi!.html.includes("Entrega os artigos à transportadora"));
  assertEquals((multi!.html.match(/Precisas de ajuda\?/g) ?? []).length, 1);
});

Deno.test("E3 estado limpo + deep link + singular/plural receção", () => {
  const bare = buildCommercialEmail("reservation_order_shipped", {
    orderId: OID,
    shipmentConfirmed: true,
    trackingCode: "ABC123",
    carrierLabel: "DPD",
    handedToCarrier: false,
    lines: [{ title: "Casaco" }],
  });
  assert(bare != null);
  assert(bare!.html.includes("ABC123"));
  assert(bare!.html.includes("Estado"));
  assert(bare!.html.includes("Transportadora"));
  assert(bare!.html.includes("Código de seguimento"));
  assert(!bare!.html.includes("está a caminho"));
  assert(!bare!.html.includes("border-radius:999px"));
  assertEquals(bare!.ctaUrl, DEEP);
  assert(bare!.html.includes("Quando receberes o artigo, confirma a receção"));
  assert(!bare!.html.includes("Quando receberes os artigos"));

  const onWay = buildCommercialEmail("reservation_order_shipped", {
    orderId: OID,
    shipmentConfirmed: true,
    trackingCode: "ABC123",
    carrierLabel: "DPD",
    handedToCarrier: true,
    lines: [{ title: "Casaco" }, { title: "Cachecol" }],
  });
  assert(onWay!.html.includes("está a caminho"));
  assert(onWay!.html.includes("Quando receberes os artigos, confirma a receção"));
  const ctaCount = (onWay!.html.match(/Acompanhar encomenda/g) ?? []).length;
  assertEquals(ctaCount, 1);
});

Deno.test("E3 só com shipmentConfirmed", () => {
  assertEquals(canSendShippedEmail({ shipmentConfirmed: true }), true);
  assertEquals(canSendShippedEmail({}), false);
});

const DEMO =
  "https://picsum.photos/seed/fleaber-delta-142/600/800";

Deno.test("shipping_delta_requested — buyer, sem 2.ª proteção, deep link", () => {
  const e = buildCommercialEmail("shipping_delta_requested", {
    orderId: OID,
    weightBandFrom: "0_3",
    weightBandTo: "3_6",
    shippingDeltaCents: 150,
    amountChargeCents: 150,
    fleaberProtectionCents: 0,
    payDeadlineAt: "2030-01-15T18:00:00.000Z",
    audienceRole: "buyer",
    lines: [
      { title: "Casaco TESTE", priceLabel: "18,00 €", imageUrl: DEMO },
    ],
  });
  assert(e != null);
  assertEquals(e!.ctaUrl, DEEP);
  assert(e!.html.includes("Diferença de portes"));
  assert(e!.html.includes("não</strong> é uma nova compra") || e!.html.includes("não é uma nova compra") || e!.html.includes("não</strong> é uma nova"));
  assert(e!.html.includes("Proteção Fleaber adicional") || e!.html.includes("não</strong> inclui Proteção"));
  assert(!e!.html.includes("nova venda"));
  assert(e!.html.includes(DEMO));
  assert(e!.html.includes("1,50 €"));
});

Deno.test("shipping_delta_paid — buyer vs seller", () => {
  const buyer = buildCommercialEmail("shipping_delta_paid", {
    orderId: OID,
    amountChargeCents: 150,
    audienceRole: "buyer",
    lines: [{ title: "X", imageUrl: DEMO }],
  });
  assert(buyer!.html.includes("não</strong> é uma nova compra") || buyer!.html.includes("nova compra"));
  assert(buyer!.subject.includes("confirmada"));
  assertEquals(buyer!.ctaUrl, DEEP);

  const seller = buildCommercialEmail("shipping_delta_paid", {
    orderId: OID,
    amountChargeCents: 150,
    audienceRole: "seller",
    lines: [{ title: "X" }],
  });
  assert(seller!.html.includes("não</strong> é uma nova venda") || seller!.html.includes("nova venda"));
  assert(seller!.subject.includes("podes enviar") || seller!.html.includes("preparar o envio"));
  assertEquals(audienceRoleFromDedupe("shipping_delta_paid", `ship_delta:${OID}:paid:buyer`), "buyer");
  assertEquals(audienceRoleFromDedupe("shipping_delta_paid", `ship_delta:${OID}:paid`), "seller");
});

Deno.test("datas sempre DD/MM/AAAA", () => {
  const s = formatDeadlinePt("2030-01-15T18:00:00.000Z");
  assert(s != null);
  assert(/^\d{2}\/\d{2}\/\d{4}/.test(s!));
  assertEquals(formatDeadlinePt("2030-01-15T18:00:00.000Z", { withTime: false }), "15/01/2030");
  const rf = refundStatusCopy({ refundStatus: "initiated" });
  assertEquals(rf.title, "Reembolso iniciado");
  const done = refundStatusCopy({ refundStatus: "completed" });
  assertEquals(done.title, "Reembolso concluído");
});

Deno.test("cancelamentos — reembolso iniciado vs concluído + deep link", () => {
  const expired = buildCommercialEmail("shipping_delta_expired_cancelled", {
    orderId: OID,
    audienceRole: "buyer",
    refundHint: DEFAULT_REFUND_HINT,
    refundStatus: "initiated",
    lines: [{ title: "Y" }],
  });
  assert(expired!.html.includes("Reembolso iniciado"));
  assert(!expired!.html.includes("Reembolso concluído"));
  assert(expired!.html.includes("Reembolso integral") || expired!.text.includes("Reembolso integral"));
  assertEquals(expired!.ctaUrl, DEEP);

  const done = buildCommercialEmail("shipping_delta_expired_cancelled", {
    orderId: OID,
    audienceRole: "buyer",
    refundStatus: "completed",
    lines: [{ title: "Y" }],
  });
  assert(done!.html.includes("Reembolso concluído"));
  assert(!done!.html.includes("Reembolso iniciado"));

  const deadline = buildCommercialEmail("ship_deadline_auto_cancelled", {
    orderId: OID,
    audienceRole: "seller",
    shipByAt: "2030-02-01T12:00:00.000Z",
    refundHint: DEFAULT_REFUND_HINT,
    refundStatus: "initiated",
    lines: [{ title: "Y" }, { title: "Z" }],
  });
  assert(deadline!.html.includes("prazo de envio"));
  assert(deadline!.html.includes("Reembolso iniciado"));
  assert(/01\/02\/2030/.test(deadline!.html) || /01\/02\/2030/.test(deadline!.text));
  assertEquals(deadline!.ctaUrl, DEEP);
});
