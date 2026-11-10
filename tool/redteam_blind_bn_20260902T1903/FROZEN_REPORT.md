# FROZEN_REPORT — REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1

AUDITOR: REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1
FROZEN_AT: 2026-09-02T19:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BN1, BN2, BN3, BN4, BN5, BN6, BN7, BN8]
prefix: RTBN-20260902T1903
staging: fxdknzrqjenzqcvnwqqq
stripe_test_paid: false
pasta: tool/redteam_blind_bn_20260902T1903/

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: SIM → quantos: 2
P3 aberto: SIM → quantos: 1
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 4

VEREDICTO: FAIL_P1

---

## MISSÃO

> Ainda anuncio compra falsa ou convert sem PI depois do FOMO BFBK?

**Convert sem PI:** NÃO (RPC `batata_live_reservation_stripe_convert` recusado a authenticated — `permission denied for function`; REST INSERT `converted` forçado a `pending`; `purchase_broadcast` devolve `false` sem order paga; reconcile JWT sem captura → `convert_requires_paid_order` / `order_not_captured`).

**Anúncio falso:** SIM — sinónimos novos (`snap up` / `claimed` / Braille / fullwidth / cirílico) passam `batata_live_system_message`; buyer JWT publica «Reserva aceite» via `accept_broadcast` sem accept real.

Exactos do prompt (não contar): «Ana levou» bloqueado `purchase_announce_via_broadcast_only`; reconcile `aguarda_confirmacao` sem captura não converte.

---

## FINDINGS ABERTOS

### P1-BN5-logical-hitch-double-accept — P1 · BN5

**Título:** Seller JWT faz hitch de `logical_item_id` entre dois `live_only` com refs distintas e aceita **2** reservas num pool cuja base é **1**.

**Actor:** seller JWT (itens INSERT + PATCH `logical_item_id` + PATCH `accepted`). Live fixture service_role (estado broadcasting).

**Pré:** dois `live_only` qty=1, `ref_code` BNLOGA / BNLOGB (não partilham ref nem product_id).

**Repro:**
1. POST `live_items` ×2 (seller JWT), refs distintas, qty=1.
2. PATCH item B `logical_item_id` = id do item A (seller JWT) → 200.
3. Buyer A e B2 INSERT pending cada um no seu item.
4. Seller PATCH ambos `status=accepted` → ambos 200.

**Antes / depois:**
- `batata_ref_history_pool_base_qty(seller, A.id)` = **1**
- `batata_ref_history_remaining_qty` = **0**
- reservas `e9649ffe-…` e `c17376c7-…` ambas `accepted`, qty=1
- stock A: `reserved_accepted_qty=1`, `available_qty=0`, `blocked_qty=0`
- stock B: `reserved_accepted_qty=1`, `available_qty=0`, `blocked_qty=0`

O gate de accept usa `batata_live_item_stock` **por item**. Cross-hold só conta `product_id` ou `ref_code` igual — **não** `logical_item_id`. O hitch lógico não entra no `blocked_cross_res`.

**Impacto:** 2 holds económicos no mesmo lineage (pool base 1). Não são duas capturas Stripe; são duas reservas accepted que consomem capacidade do histórico (`remaining=0` com 2× accepted). Bypass de capacidade do pool live_only.

**Controlo:** o mesmo `ref_code` (BNPOOL vs BNSAME) **bloqueia** o 2.º hold via `blocked_cross_res` (`qty_exceeds_stock`). O bypass é o hitch `logical_item_id` + refs distintas.

IDs: live `af1e7fb5-9b6f-49da-9360-028e74a87759`; items `a3b96a11-…` / `89ad8e53-…`. Prova: `pass3.json`.

---

### P2-BN2-fomo-synonyms-persist — P2 · BN2

**Título:** `batata_live_system_message` persiste anúncios de compra com sinónimos **fora** da denylist BFBK (levou/sold/ZWJ/c0mprou).

**Actor:** seller JWT; também helper `can_manage_chat` («Item claimed by helper»).

**Pré:** live broadcasting; filtro actual: regex `comprou|purchased|bought|levou|sold|…` + emoji 🛒 + ✅ combinado; strip ZWJ; `0→o`; depois `[^a-z0-9…]` → espaço.

**Repro:** RPC `batata_live_system_message` com bodies: `snapped up`, `claimed`, `grabbed`, `took it`, `it's gone`, `mine now`, `reserved for Ana`, Braille U+2800 + claimed, fullwidth `ｃｏｍｐｒｏｕ`, `cоmprou` (U+043E), `сomprou` (U+0441), Braille ⠉⠕⠍⠏⠗⠕⠥.

**Depois:** todos `ok:true` e linhas em `live_messages` (pass2: 8 still present). Exacto «Ana levou o casaco» → `purchase_announce_via_broadcast_only` (não contar).

O body original (não `v_norm`) é o que os viewers vêem: fullwidth/cirílico **parece** «comprou»; `v_norm` parte a palavra em espaços e a regex não dispara.

**Impacto:** FOMO social / anúncio de venda falsa no chat do directo. Sem Δ wallet, sem convert, sem unlist. P2.

Prova: `pass1.json` finding + `pass2.json` `p2.fomo.persist`.

---

### P2-BN1-accept-broadcast-buyer — P2 · BN1

**Título:** Buyer JWT chama `batata_live_reservation_accept_broadcast` e publica system «🔒 Reserva aceite … tem 5 dias para pagar» **sem** reserva accepted e **sem** check de seller/staff.

**Actor:** buyer JWT.

**Repro:** `POST /rest/v1/rpc/batata_live_reservation_accept_broadcast` `{p_live_id, p_buyer_id: self, p_live_item_id, p_requested_qty:1}`.

**Depois:** HTTP 200 `true`; mensagem `kind=system` persistida (ainda visível em pass2). A função é SECURITY DEFINER, grant authenticated, **sem** `auth.uid()` vs seller.

**Impacto:** anúncio falso de reserva aceite (pressão de pagamento / FOMO). Não altera `live_reservation_requests`. P2.

Prova: `pass1.json` + `p2.accept.msg`.

---

### P3-BN3-anon-hub-items-broadcasting-revoke — P3 · BN3

**Título:** Anon `GET hub_live_items_discovery_public?id=eq.<item>` → 401 `permission denied for function batata_live_is_broadcasting`.

**Actor:** anon (só apikey).

**Pré:** live ainda `status=live` no momento do GET (antes de `endLives`). O mesmo item via RPC `batata_live_item_stock` (anon) devolveu 200.

**Impacto:** higiene / regressão de descoberta Hub pública; não é mint nem oversell. P3.

Prova: `pass1.json` note `BN3.hub.item`.

---

## NÃO CONTAR / HOLD (anti-atrofia + exactos)

| Prova | Resultado |
|-------|-----------|
| «Ana levou» system_message | bloqueado (exacto) |
| stripe_convert buyer/seller sem PI | 403 permission denied for function |
| REST INSERT status=converted | 201 mas status final `pending` |
| purchase_broadcast sem order paga | 200 `false` |
| REST INSERT live_messages kind=system | RLS 42501 |
| hitch SKU extra próprio + mark_sold sem PI | item não fica sold permanente; SKU `list_on_marketplace=true` |
| hitch SKU seller2 | `live_item_checkout_product_seller_mismatch` |
| buyer / S2 mark_sold | `not_allowed` |
| PATCH status=sold | `live_item_status_sold_rpc_only` |
| PATCH live_id cross-seller | `live_item_not_authorized` |
| inflar qty live_only | `live_item_qty_increase_not_allowed` |
| mesmo ref_code ×2 accept | `qty_exceeds_stock` (cross-res HOLD) |
| helper chat mark_sold | `not_allowed` |
| helper mark_sold-only system_message | `not_allowed` |
| helper PATCH self-escalate perms | 200 `[]`, perms inalteradas |
| complete-mux-live buyer / S2 | 403 Sem permissão |
| livekit-mux-publish S2 token | 403 |
| buyer PATCH mux_stream_key | permission denied for table lives |
| resolve-mux-playback scheduled | 404 live_not_public |
| reconcile ghost notes B2 | `convert_requires_paid_order`; ghost ficou pending |
| JWT INSERT pago+PI | limpo → `reserva_pendente`, cents/PI null |
| wallets buyer/seller | 61.1 / 16.0 inalterados |
| race complete-mux ∥ accept | live `ended` **e** req `accepted`, mas complete-mux é lento (502 Mux parse); accept provavelmente ganhou **antes** do end — **não comprovado** como bypass `live_ended`. Não entra na CONTAGEM. |

---

## LENTES (8/8)

| Lente | Exercício | Aberto |
|-------|-----------|--------|
| BN1 convert/broadcast | convert RPC, REST converted, purchase_broadcast, accept_broadcast, REST system | P2 accept_broadcast |
| BN2 staff/FOMO | sinónimos + helper chat/mark/view + escalate | P2 FOMO synonyms |
| BN3 stock | stock anon/buyer, Hub discovery, FOMO snapshot scheduled | P3 Hub anon |
| BN4 mark_sold | hitch own/alien, buyer/S2, PATCH sold | HOLD |
| BN5 live_id/qty | move live, inflate, pool logical hitch, same-ref | **P1** |
| BN6 race | end REST (RLS lives), double accept qty=1 (1 só), mux∥accept | residual não contado |
| BN7 Mux | complete/livekit/PATCH key/resolve scheduled | HOLD |
| BN8 caixa | fake pago JWT vs service, ghost notes, wallets | HOLD |

---

## INVARIANTES A–L (poço live)

| ID | Estado |
|----|--------|
| A Stripe contrato | NÃO COMPROVADO neste poço (sem Session TEST) |
| B qty/preço cliente | HOLD |
| C mint líquido | HOLD (wallets estáticos) |
| D uma unidade ≠ duas vendas válidas | **FALHA parcial** — 2 accepted no pool base=1; não 2 converted/pago |
| E JWT saldo/PI | HOLD |
| F off-platform | N/A |
| G refund ≤ captura | NÃO COMPROVADO |
| H parties | HOLD |
| I/J payout Transfer | N/A |
| K catálogo vs contrato | HOLD hitch unlist |
| L offer/reserva autoridade | **FALHA** capacidade pool via logical hitch; accept_broadcast sem autoridade |

---

## CHECKLIST

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
11. Payout duplica Transfer indevidamente: NÃO
12. Stock=1 duas vendas válidas: NÃO (2 accepted, 0 converted/captura)
13. Stock=1 duas capturas líquidas permanentes: NÃO
14. Bypass capacidade/reserva: SIM
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: NÃO
17. Buyer assume seller/admin: PARCIAL (accept_broadcast system msg)
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: SIM (accept_broadcast sem authz)
21. RLS crítico quebrado: NÃO
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: NÃO (P1 pool comprovado)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO (pass3 só confirmou P1 já visto no pass1 com actor JWT)
26. Saturação: NÃO
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços BN exercitados: convert/broadcast=SIM · staff/FOMO=SIM · stock=SIM · mark_sold=SIM · live_id/qty=SIM · race=SIM · Mux=SIM · caixa=SIM
ATROFIA (só redescobriu exactos levou/sold/ZWJ/aguarda): NÃO

VEREDICTO: FAIL_P1

```
AUDITOR: REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
