# FROZEN_REPORT — REDTEAM_BLIND_AJ_LIVE_POS_AEAFAG_v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 1
P3 aberto: SIM          → quantos: 1  (fora de âmbito salvo pedido)
```

**VEREDICTO:** `FAIL_P1`

```
AUDITOR: REDTEAM_BLIND_AJ_LIVE_POS_AEAFAG_v1
FROZEN_AT: 2026-09-02T07:48:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AJ1, AJ2, AJ3, AJ4, AJ5, AJ6, AJ7, AJ8]
VEREDICTO: FAIL_P1
```

Prefixo fixtures: `RTAJ-20260902T0728-`  
Staging: `fxdknzrqjenzqcvnwqqq`  
Probes: `tool/redteam_blind_aj_20260902T0728/` (`pass1.dart` … `pass3.dart`, `pass1.json` … `pass3.json`)

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO (poço live; Stripe TEST não exigido para o P1)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (fora do poço)
16. Stock=1 duas vendas válidas — NÃO (2.ª order `order_live_item_exhausted` / accept `qty_exceeds_stock`)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO (sem captura TEST)
18. Bypass capacidade/reserva — NÃO (convert sem PI bloqueado; race accept 1/2)
19. Cross-user financeiro — NÃO (Δ wallet = 0)
20. Cross-user dados sensíveis — NÃO (stream_key REST 403)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO (fora do poço)
24. RPC SECURITY DEFINER perigoso executável — PARCIAL (mark_sold autenticado faz unlist alheio; `stripe_convert` 403)
25. RLS crítico quebrado — NÃO (lives PATCH alheia 403; live_items alheia 403)
26. Edge confia total do cliente — NÃO (`livekit-mux-publish` / `complete-mux-live` 403 na live alheia)
27. Regressão funcional (happy path partido) — NÃO (código não alterado)
28. Saturação atingida — SIM (último passe = mesma classe P1, sem classe nova)

ATROFIA_ABORT: NÃO (≥50% exactos AG/AD/AA: não)

--------------------------------------------------
## FINDING P1 — AJ4-02
--------------------------------------------------

**ID:** AJ4-02 (variantes AJ4-02b, AJ4-06, AJ4-09, AJ4-01 no próprio SKU)  
**Lentes:** AJ4 · AJ3 · AJ7  
**Sev:** P1  
**Título:** `mark_sold` em `live_only` deslista `checkout_product_id` sem PI e sem ser dono do produto

**Actor:** seller JWT (vendedor A)

**Pré:**
- Live A do seller A (`status=live`)
- `live_items.item_kind=live_only` com `checkout_product_id` = UUID de um `products` do seller2
- Sem order paga, sem `amount_paid_cents`, sem PaymentIntent
- Guard AA/AEAFAG: `marketplace_product` só deslista com order paga; ramo `else` (live_only) deslista `checkout_product_id` sem essa prova

**Request (repro):**
1. `POST /rest/v1/live_items` JWT seller A: `{ live_id, item_kind:'live_only', quantity:1, checkout_product_id:<uuid_seller2> }` → 201
2. (alt) INSERT sem checkout, depois `PATCH live_items` `{ checkout_product_id:<uuid_seller2> }` → 200
3. `POST /rest/v1/rpc/batata_mark_live_item_sold` `{ p_live_item_id }` JWT seller A → 200 `ok:true`

**Antes (produto seller2):** `is_sold=false`, `list_on_marketplace=true`  
**Depois:** `is_sold=true`, `list_on_marketplace=false`  
**Item live:** `status` volta a `available` (recompute); o mesmo item serve para um segundo SKU (AJ4-09)

**Impacto:**
- Qualquer vendedor autenticado que conheça o UUID do produto (visível em REST `products` para buyers) marca o catálogo alheio como vendido e tira-o da montra, **sem pagar e sem ser staff**.
- Buyer a criar order no SKU vítima após o unlist → `order_hold_exceeds_stock` (DoS de venda).
- Seller2 **consegue** relistar (`PATCH is_sold=false, list_on_marketplace=true` → 200). É sabotagem reversível, não mint. Continua P1: escala a todos os SKUs cujo id seja público; o item live não fica `sold`, logo o ataque é repetível.
- Δ wallet: 0. Sem captura Stripe.

**Hub:** `hub_products_public` esteve vazio **antes e depois** nos fixtures (perfil/demo). Superfície Hub **não comprovada**. Prova = tabela `products` + REST buyer + order bloqueada.

**Não é** o exacto AG4 (RPC mark_sold partido) nem AD3 PATCH `status=sold`. O RPC **funciona**; o buraco é o ramo live_only sem check de dono/PI.

**Repro ids (pass2):** victim `f0d4f335-8ab9-495e-bdb7-ae7cc689275e` (seller2 `698a9b96-…`); item `b559f603-…`; PATCH variant `2851dfc7-…`.

--------------------------------------------------
## FINDING P2 — AJ3-HUB-ANON
--------------------------------------------------

**ID:** AJ3-HUB-ANON  
**Lente:** AJ3  
**Sev:** P2  
**Título:** Views Hub de live_items falham para anon (`batata_live_item_stock` sem GRANT)

**Actor:** anon (sem JWT)

**Request:** `GET /rest/v1/hub_live_items_public?id=eq.…` e `hub_live_items_discovery_public`  
**Obtido:** `401 permission denied for function batata_live_item_stock`  
**FOMO:** `POST rpc/batata_hub_live_fomo_snapshot` → 200 (granted a anon)

As views são `GRANT SELECT` a anon mas chamam um RPC que anon não pode executar. Catálogo Hub de artigos de live ilegível sem sessão. Não é o ghost AD3/AG3 (item esgotado visível); é superfície pública partida.

--------------------------------------------------
## FINDING P3 — AJ4-03
--------------------------------------------------

**ID:** AJ4-03  
**Lente:** AJ4  
**Sev:** P3  
**Título:** INSERT `live_items.status=sold` (o guard só bloqueia UPDATE)

**Actor:** seller JWT  
**Request:** `POST live_items` `{ status:'sold', item_kind:'live_only', quantity:1 }` → 201 `status=sold`  
Buyer/Hub não vêem o item (oculto). Higiene do invariante «sold só via RPC».

--------------------------------------------------
## HOLD (poço — não exactos AG/AD/AA)
--------------------------------------------------

| Lente | Tentativa nova | Resultado |
|-------|----------------|-----------|
| AJ1 | `batata_live_reservation_stripe_convert` JWT | 403 permission denied |
| AJ1 | `process` `convert` pending sem PI | `convert_requires_paid_order` |
| AJ1 | INSERT `converted` `source=ocr_manual` | 403 `convert_requires_paid_order` |
| AJ1 | INSERT `accepted` `source=instagram` | 403 RLS |
| AJ1 | PATCH order `paid` EN + reconcile/sync | order fica `reserva_pendente`; reconcile `order_not_paid` |
| AJ1 | um PI → duas converts | fixture order live_only recusada; convert continua a exigir pago |
| AJ2 | view-only `mark_sold` | `not_allowed` |
| AJ2 | view-only PATCH item / end live | 403 |
| AJ2 | self-escalate permissions | permissions intactas |
| AJ2 | helper INSERT live_item | RLS 403 |
| AJ4 | `mark_sold` `marketplace_product` sem PI | produto **não** deslista (invariante AA HOLD) |
| AJ4 | buyer PATCH `checkout_product_id` | 200 [] (sem efeito) |
| AJ5 | UPDATE `live_id` com reservas | `live_item_live_id_immutable` |
| AJ5 | `product_id` de outro seller | `live_item_product_seller_mismatch` |
| AJ5 | mesmo SKU em duas lives → 2 orders | `order_live_item_exhausted`; accept `qty_exceeds_stock` (não oversell) |
| AJ6 | 2× accept qty=1 paralelo | 1 accepted |
| AJ6 | 2× convert paralelo | ambos `convert_requires_paid_order` |
| AJ7 | PATCH lives alheia | 403 table lives |
| AJ7 | livekit token / complete-mux live alheia | 403 |
| AJ7 | REST `mux_stream_key` | 403 |
| AJ7 | `batata_live_system_message` live alheia | `not_allowed` |
| AJ7 | INSERT live_item na live alheia | `live_item_not_authorized` |
| AJ8 | INSERT order `pago` JWT | não persistiu como pago fantasma |
| AJ8 | Δ wallet | 0 (buyer 61.10 / seller 17.97) |
| AJ8 | tip checkout live alheia | 400 |

**Não contado como finding:** INSERT `live_only` `quantity=99` — criação de stock live_only (o bloqueio AEAFAG é no UPDATE).

--------------------------------------------------
## INVARIANTES A–L (poço live)
--------------------------------------------------

| ID | Estado |
|----|--------|
| A | NÃO COMPROVADO (sem Checkout TEST neste poço) |
| B | HOLD |
| C | HOLD (sem mint; Δwallet 0) |
| D | HOLD neste poço (não 2 vendas válidas) |
| E | HOLD |
| F | HOLD |
| G | NÃO COMPROVADO |
| H | HOLD (seller_id da reserva forçado ao dono da live) |
| I | NÃO COMPROVADO |
| J | NÃO COMPROVADO |
| K | FALHA parcial — catálogo alheio alterado por JWT sem contrato pago (AJ4-02) |
| L | HOLD convert; FALHA mark_sold live_only+checkout |

--------------------------------------------------
## MISSÃO (resposta directa)
--------------------------------------------------

> Depois dos fechos AEAFAG live, ainda consigo convert/mark_sold sem PI, esgotar stock via Hub/discovery fantasma, ou sabotar live alheia?

- **Convert sem PI:** não (RPC process, PATCH/INSERT, stripe_convert, reconcile unpaid).
- **mark_sold sem PI:** **sim**, no ramo `live_only` + `checkout_product_id` (inclui produto de outro vendedor). `marketplace_product` sem PI **não** deslista.
- **Hub/discovery fantasma de esgotado:** não comprovado (views Hub live_items **401 anon**; INSERT sold oculto a buyer).
- **Sabotar live alheia (Mux/end/item):** não. **Sabotar catálogo alheio via mark_sold:** sim (P1).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
