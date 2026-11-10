## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

1. P0? NÃO
2. Quantos P0: 0
3. P1? SIM
4. Quantos P1: 1
5. P2? NÃO
6. Quantos P2: 0
7. P3? NÃO
8. Quantos P3: 0

--------------------------------------------------
AUDITOR: REDTEAM_BLIND_BX_MARKETPLACE_POS_BRBW_v1
FROZEN_AT: 2026-09-06T11:55:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BX1, BX2, BX3, BX4, BX5, BX6, BX7, BX8]
VEREDICTO: FAIL_P1
--------------------------------------------------

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTBX-20260906T1135-`
Actors: anon · buyer JWT · seller JWT · B2 · S2
service_role: só fixture / observação (`setup_paid_order`, `setup_paid_bag`, SELECT)
Pasta: `tool/redteam_blind_bx_20260906T1135/`
Exactos BR/BF **não contados:** 3 sacos A∩B∩C · AB∥AC dual · hífen+compact.

--------------------------------------------------
MISSÃO
--------------------------------------------------
Depois do claim atómico BRBW, ainda 2 Sessions ou total abaixo do contrato?
Variantes novas: anel de 4 sacos · bag+single paralelo mesma order · metadata
drift pós-claim · currency ZWJ · offer freeze Unicode · settle Session orphan list.

--------------------------------------------------
FINDINGS PROVADOS
--------------------------------------------------

### RTBX-BX2-BAG-SINGLE-DUAL-OPEN · P1 · BX2/BX6

**Título:** Corrida bag∥single na mesma encomenda deixa **duas** Checkout Sessions
abertas e pagáveis para o mesmo saco (€24,28 cada).

**Actor:** buyer JWT

**Pré:** 2 orders marketplace do mesmo vendedor (16 € + 9 €), status
`reserva_pendente`. 6 POST em paralelo: 3× `bag_checkout` das duas linhas +
2× single da linha cara + 1× single da linha barata.

**Repro:**
1. INSERT 2 products + 2 orders (JWT buyer).
2. `Future.wait` de 6 `create-payment-intent` (bag e single misturados).
3. BD fica com **um** `stripe_checkout_session_id` partilhado nas duas linhas
   (`cs_test_a1ApeaJpbFbBiO0g1sxxtvaU8kxD9nUI7UGB5FK8nBxQK9rNcmcolegzQy`).
4. Um dos POST bag devolveu **outro** `cs_test_…` (`cs_test_a18lxMlgcEtfcoAs7VPMxHyPxWqFhkE6qOhE9dMdn0x6ohbT1SYcGvpqIL`)
   que **não** ficou nas orders.
5. Abrir as duas URLs completas (com `#fid…`) no Stripe Checkout TEST.

**Esperado:** claim atómico + expire — no máximo 1 Session `open` para o saco.

**Obtido:**
- Session na BD: **aberta**, UI «Saco Fleaber» **€24,28**, botão Pay.
- Session órfã da corrida: **aberta**, UI «Saco Fleaber» **€24,28**, botão Pay.
- Singles mais baratos da mesma corrida (€17,45 / €10,10): **expirados**
  («You’re all done here»).

**Impacto:** o cliente (ou quem interceptar a resposta HTTP) fica com um URL
pagável que a BD já não aponta. Pagar as duas Sessions cobraria 2× €24,28
sobre o mesmo par de encomendas. **Captura dupla não foi liquidada nesta
ronda** (SESSION CRIADA ≠ CAPTURA) — por isso P1, não P0.

**Prova:** `pass2_bagsingle_urls.json` · `pass2_browser.json` · screenshots
Stripe Checkout (kept + leftover).

Orders: `1429d621-0839-424f-995c-a1b742dde543`,
`c50a41c8-f77d-4527-ae26-0aac2354896c`.

--------------------------------------------------
RETRAÍDOS (não contar)
--------------------------------------------------

- **RTBX-BX7-ANON-CHECKOUT** — falso positivo do passe 1: `checkout(jwt: null)`
  usava `jwt ?? buyerJwt`. Passe 2 com `Authorization: Bearer <anon>` →
  `400 Invalid checkout user.`
- **RTBX-BX2-RING4-SPLIT-SID** — a BD ficou com DA em A+D e (passe 1) BC em
  B+C: pares **disjuntos**, não dual sobre a mesma order. URLs leftover do
  anel (AB, CD, DA extra) no browser: **expiradas**. Não é finding.

--------------------------------------------------
DEFESAS QUE AGUENTARAM
--------------------------------------------------

**BX1 preço:** `amount=1` ignorado (quote 1955 cêntimos num SKU 18 €). Drop de
catálogo 20→1 € após claim: Session manteve 2711 (contrato selado 2000+800).
ZWJ / ZWNJ / cirílico / `usd` → `only EUR is supported`. BOM/NBSP passam o
`trim()` JS e continuam EUR (sem underpay).

**BX2 claim / metadata:** RPC `batata_bag_checkout_claim` 403 JWT / 401 anon.
`product_id` trocado no saco → `bag product does not match order`.
`bag_product_ids` extra no body não baixou o total. PATCH buyer `product_id`
pós-claim não alterou o SKU na BD.

**BX2 anel 4:** leftovers sobrepostos expirados; BD não ficou com 2 SID na
mesma order.

**BX3 oferta / conjunto:** amount Unicode (ZWJ, fullwidth, NBSP) → `22P02`.
Accept + PATCH amount → `offer_amount_immutable`. Checkout selado 600
cêntimos / Session 695. qty=3 na oferta → `offer_quantity_must_be_one`.
Saco 1/3 do conjunto → `bag must include all items in the accepted bundle`.

**BX4 FSM / settle:** order `pago` → `cannot start payment`. GET
`session_id=cs,cs_orphan` / JSON array / espaço → 400/402, orders continuam
`reserva_pendente`. `fase2_e2e_settle` com JWT buyer → `401 service_role required`.

**BX5 stock:** 2.º hold stock=1 → `order_hold_exceeds_stock`.

**BX7 2.º actor:** B2 na order B1 → `order does not belong to buyer`. Saco
dois vendedores → `bag lines must share one seller`. Anon (passe 2) recusado.

**BX8 caixa:** `setup_paid_order` Stripe TEST `pago` + PI
`pi_3UCdZOH7FWYUN3jh08p8vyPJ` 590 cêntimos, `stock_units_applied=1`.
`setup_paid_bag` PI `pi_3UCda8H7FWYUN3jh1LETsnOc` 1115 cêntimos.

Compra legítima single e saco multi-SKU **não** partiram.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------

1. Checkout Stripe TEST pago marketplace: sim (`setup_paid_order` + `setup_paid_bag`).
2. Contabilidade fechada no fluxo pago (stock · PI · status). Dual Session
   órfã **não** capturada em duplicado.
3. Race `Future.wait`: anel 4×2; bag∥single 6 vias.
4. Payload mutation: currency ZWJ, metadata extra, product_id swap, amount=1.
5. Buyer fresco B2 + anon + seller2.
6. Distinção SESSION CRIADA ≠ CAPTURA: leftover bag **open** comprovado na UI;
   singles/anel leftover **expired**.

--------------------------------------------------
INVARIANTES (A–L) neste poço
--------------------------------------------------

| ID | Estado |
|----|--------|
| A | HOLD no quote servidor; FALHA parcial — 2 Sessions open mesmo montante (captura 2× não provada) |
| B | HOLD (amount/currency/metadata cliente) |
| C | NÃO COMPROVADO (dual captura não liquidada) |
| D | HOLD holds stock=1; dual Session open é risco de 2 capturas no mesmo par |
| E | HOLD |
| F | NÃO EXERCITADO (MB WAY fora do poço novo) |
| G | NÃO COMPROVADO |
| H | HOLD (B2/anon/cross-seller) |
| K | HOLD (catálogo após selo) |
| L | HOLD (oferta freeze + bundle incompleto) |

--------------------------------------------------
CHECKLIST 28
--------------------------------------------------

1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: SIM
4. Quantos P1: 1
5. Buyer manipula preço autoritativo: NÃO
6. Buyer manipula qty autoritativa: NÃO
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO COMPROVADO
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer indevidamente: NÃO (fora do poço)
12. Stock=1 duas vendas válidas: NÃO (2.º hold bloqueado)
13. Stock=1 duas capturas líquidas permanentes: NÃO COMPROVADO
14. Bypass capacidade/reserva: NÃO
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: NÃO
17. Buyer assume seller/admin: NÃO
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO (fora do poço)
20. RPC SECURITY DEFINER perigoso executável: NÃO (`batata_bag_checkout_claim` negado)
21. RLS crítico quebrado: NÃO
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: SIM (dupla captura do leftover bag)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: SIM (bag∥single dual Session open)
26. Saturação: NÃO
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços BX: anel4=SIM · bag+single=SIM · metadata drift=SIM · currency ZWJ=SIM ·
offer freeze Unicode=SIM · settle orphan list=SIM
ATROFIA (só redescobriu exactos BR/BF): NÃO

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
