## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 2

```
AUDITOR: REDTEAM_BLIND_AZ_MARKETPLACE_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AZ1, AZ2, AZ3, AZ4, AZ5, AZ6, AZ7, AZ8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`cs_test_`) · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação / cleanup. Prefixo `RTAZ-20260902T1606-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada. Relatório AT **não** lido.

Sonda: `dart run scripts/probes/redteam_blind_az_20260902T1606.dart`  
Artefactos: `findings.json` · `matrix.json` · `notes.json` · `created.json`

Anti-atrofia: 0/2 achados = lista exacta AN-P3-01/02/03 · AH2 · AH6 · AB3 · AB5. Variantes novas (UUID compacto vs hífen, saco 15/16/20, mix bundle+extra, currency `euro`/`gbp`/`EUR`, prize no saco).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (saco 2×8€ → 1745¢ = catálogo+protecção; `currency=gbp`/`euro` 400)
10. Buyer manipula qty autoritativa — NÃO (3.º INSERT stock=2 → `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (wallet buyer 0→0, seller 0→0)
13. Refund excede captura — NÃO (S2 refund S1 unpaid → 403 `Sem permissão.`)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito marketplace)
16. Stock=1 duas vendas válidas — NÃO (stock=2: 3.ª order 400)
17. Stock=1 duas capturas líquidas permanentes — NÃO (sem captura TEST paga)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (B2 checkout B1 → 400 `order does not belong to buyer`; compact UUID igual)
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO (não sondado nesta ronda)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (`amount`/`currency`/`prize_shipping`/`line` IDs compactos de produto rejeitados ou ignorados)
27. Regressão funcional (happy path partido) — NÃO (hífen, compact order_id, mix hífen+compact, EUR uppercase, saco 15 linhas → 200)
28. Saturação atingida — SIM nas 8 lentes; P1 ainda aberto (dual Session)

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### AZ-20260902T1606-002 · P1 · AZ6 — POST paralelo hífen ∥ compact cria 2 Sessions

**Actor:** buyer JWT  
**Pré:** saco A+B (5€+5€); um body com UUIDs com hífen, o outro com 32 hex sem hífen (mesmo par de orders).  
**Repro:** `Future.wait` 2× `create-payment-intent` `bag_checkout` no mesmo par.  
**Obtido:** HTTP `[200, 200]`, `unique_sids=2`  
`cs_test_a1nGJolCbS0nGbeZjO1iPigFfnQ8EuguZXB5vyNUi1ValJtBwkVxnCZEDa`  
`cs_test_a1dckF3UCaQK45oUuu9tDe2CQA9PlapjkvbAHX97tmaSmlkW16i2LiZQ4f`  
**Impacto:** duas Checkout Sessions Stripe TEST para o mesmo saco. Quem pagar as duas URLs pode liquidar duas vezes o mesmo par (settle recomputa quote — se a 2.ª ainda `open` e a 1.ª já paga, a 2.ª deve falhar no claim `paid`; **não pago nesta ronda**). Caminho explorável, não captura provada → **P1** não P0.  
**Porque é variante nova:** não é AH6 (sacos A+B vs A+C) nem o POST idêntico AN; é o formato UUID compacto vs hífen no mesmo par, a explorar o fecho ANAS `compactBagStripeMetadata`.

### AZ-20260902T1606-001 · P2 · AZ2 — saco compact UUID não reutiliza Session

**Actor:** buyer JWT  
**Pré:** ANAS grava `bag_order_ids` **sem hífens**; o quote compara essa string com `lineQuotes.order_id` **com hífens** (`priorBag !== currentBag` → expire+create).  
**Repro:** 2× POST sequencial `bag_checkout` A+B (UUIDs com hífen, mesmo par).  
**Obtido:** `sid1 ≠ sid2`, `reused_session=null`. Orders ficam apontadas para `sid2`. GET settle unpaid → **402** (não liquida). Compact `order_id` no body **funciona** (200, 1745¢). Mix hífen+compact no body **funciona**. REST `id=eq.<32hex>` encontra a row (expire `.eq` PG uuid **não** é o furo).  
**Impacto:** cada POST sequencial expira a Session anterior e cria outra. Não ficou URL antiga viva **provada** (página Stripe ~552kB contém a palavra `expired` no JS — heurística inútil). Hygiene: churn de `cs_`, janela de corrida maior (→ P1 acima). Sem captura dupla sequencial. **P2**.

--------------------------------------------------
## LENTES (8/8)
--------------------------------------------------

### AZ1 preço
- `currency=EUR` → 200, 18,00€ → **1955¢** (1800+155 protecção).  
- `currency=euro` / `gbp` → 400 `only EUR is supported.`  
- Produto `price=0` **não** entrou no catálogo (sem linha `gift_zero`); JWT não listou brinde 0€.  
- Quote saco 8+8€ = **1745¢** = esperado. Sem selo abaixo do catálogo.

### AZ2 session / saco
- Compact vs hífen: **P2** (001) + **P1** paralelo (002).  
- Body `order_id` compacto e misto: checkout **200**, mesmo montante. Settle GET unpaid **402**.  
- `bag_lines.product_id` compacto (mesmo SKU) → 400 `bag product does not match order` (hydrate só em metadata/settle, não no POST). Fail-closed; cliente oficial manda hífen.  
- **15 linhas:** compact 494 chars → Session **200**. **16** (527) e **20** (659) → 400 `bag too large for payment metadata. Split the bag.` Fecho AN-P3-01 aguenta 15, bloqueia 16+.

### AZ3 bundle / tier
- Buyer INSERT `pending` 201; PATCH `accepted`+`total_eur=1` → **403** `bundle_accept_seller_only`.  
- Seller PATCH `total_eur=1` após accept → HTTP 200 mas **não** baixou a 1€ (guard reescreve; sem finding).  
- Saco 1 item do bundle aceite + extra → 400 `bag must include all items in the accepted bundle.`  
- Saco bundle completo + extra catálogo → **400** o mesmo (extra ≠ `product_ids` do contrato). Não mistura tier com contrato aceite.  
- Oferta+tier_5: INSERT `product_offers` **falhou** (`offers=[]`); sub-variante não executada. Código: `anyNegotiatedOffer` anula tier do saco inteiro (comprador paga **mais**, não menos).

### AZ4 capturado / FSM
- `prize_shipping=true` em order marketplace → 400 `order is not a raffle prize.`  
- PATCH `cancelado` com Session aberta → 200; checkout seguinte → 400 `order status 'cancelado' cannot start payment.`  
- Settle unpaid → 402. Sem 2.ª captura.

### AZ5 stock / hold
- SKU `quantity=2`: INSERT 201, 201, **400** `order_hold_exceeds_stock`. Saco 3× não chegou a criar-se.

### AZ6 race
- **P1** 002. Compact vs hífen no mesmo par, em paralelo, devolve 2 `cs_`.

### AZ7 2.º actor
- B2 single e B2 saco compacto da order B1 → 400 `order does not belong to buyer.`  
- S2 `refund-order` order S1 → 403 `Sem permissão.`

### AZ8 gift/prize + caixa
- JWT `status=premio_rifa` → 201 mas status gravado **`reserva_pendente`** (não forja prémio).  
- `prize_shipping=true` no saco → 400 `prize shipping cannot be bag checkout.`  
- Fixture `premio_rifa` via service_role não produziu linha `prize_in_bag` (INSERT não devolveu id utilizável).  
- Δwallet unpaid: **0→0** / **0→0**.

--------------------------------------------------
## NÃO FEITO / LIMITES
--------------------------------------------------
- Sem `sk_test_` local: retrieve Session `open` vs `expired` e captura 4242 **não** feitas. P1 = duas `cs_` emitidas, não duas capturas.  
- `product_offers` INSERT JWT falhou nesta ronda — mix oferta+tier só raciocínio de código.  
- Relatório AT irmã não lido. Exactos AN-P3-01 (14 linhas), AN-P3-02 tier selado, AN-P3-03 INSERT accepted, AH2 orphan, AH6 two-open bags diferentes, AB3 usd, AB5 qty 1→9 **não** repetidos.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
