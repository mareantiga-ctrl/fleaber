# FROZEN_REPORT — REDTEAM_BLIND_AV_LIVE_POS_ANAS_v1

AUDITOR: REDTEAM_BLIND_AV_LIVE_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:19:46+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AV1, AV2, AV3, AV4, AV5, AV6, AV7, AV8]
VEREDICTO: PASS_CEGO_SATURADO

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: NÃO          → quantos: 0
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 2
```

**VEREDICTO:** P0–P2 fechados + só P3 + saturação 8/8 lentes AV → `PASS_CEGO_SATURADO`.

Anti-atrofia: 0 achados = lista exacta AP-P2-01 / AP-P3-01 / AJ4-02 / AJ4-03 / AD1. Variantes **novas** (broadcast cancelado+PI, order noutro live_item, helper `can_manage_chat` only, race accept pós-ended, INSERT/PATCH `live_messages` system, UPDATE pending pós-ended, reopen+accept). Fechos ANAS live **aguentaram** no ponto de anúncio pago / convert / mark_sold / Mux.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO (P3 apenas; ver achados P3)
6. Quantos P2: 0
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO (fora de foco live; orders money cols imutáveis)
10. Buyer manipula qty autoritativa — NÃO (`live_item_qty_increase_not_allowed` seller live_only)
11. Seller falsifica pagamento plataforma — NÃO (convert/broadcast exigem status pago + PI/cents; cancelado+PI recusado)
12. JWT cria saldo/fundos — NÃO (Δ wallet = 0)
13. Refund excede captura — NÃO (sem captura TEST paga nesta ronda)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (sem captura/payout)
16. Stock=1 duas vendas válidas — NÃO (AV6-05: nAcc=1; 2.º ficou pending)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO (sem Stripe TEST pago)
18. Bypass capacidade/reserva — NÃO (INSERT ended → `live_ended`; UPDATE pending→accepted ended → `live_ended`; race end∥accept → `live_ended`)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (`mux_stream_key` GRANT denied)
21. Buyer assume seller/admin — NÃO (mark_sold / complete-mux / create-mux / PATCH lives)
22. Seller assume buyer/admin — NÃO (seller2 mark_sold / LiveKit token / ownership PATCH)
23. Reviews forjadas — NÃO (fora de âmbito live)
24. RPC SECURITY DEFINER perigoso executável — NÃO para actor não autorizado (`system_message` buyer/seller2 → `not_allowed`; `purchase_broadcast` sem pago → false)
25. RLS crítico quebrado — NÃO (`live_messages` INSERT system 403; reservations mismatch 403)
26. Edge confia total do cliente — NÃO (`complete-mux-live` / `livekit-mux-publish` owner check; `create-mux-live` só vendedor)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — SIM (8/8 lentes AV; variantes novas além da lista AP/AJ/AD)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ÂMBITO E ACTORS
--------------------------------------------------

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST **não** usado (nenhum P0 exigiu captura).  
JWT: buyer / seller (LIVE_OPS) + buyer2 / seller2 / helper criados por admin (fixture).  
`service_role` só fixture / observe / cleanup.

Prefixo: `RTAV-20260902T1608-`.

Código estudado: `batata_live_purchase_broadcast`, `batata_live_system_message`, `batata_mark_live_item_sold`, `batata_process_live_reservation_request`, `batata_live_reservation_guard_authority`, `batata_live_reservation_requests_guard_live_active`, `batata_live_item_stock`, RLS `live_items` / `live_messages` / `lives`, Edge `complete-mux-live` / `create-mux-live` / `livekit-mux-publish`. Relatórios AP/AJ/AG/AD/ANAS **não lidos** antes de congelar.

Probes: `tool/redteam_blind_av_20260902T1608/pass1.dart` · `pass2.dart` · `pass3.dart`.

--------------------------------------------------
## ACHADOS P3
--------------------------------------------------

### AV-P3-01 — Helper `can_manage_chat` publica system «✅ comprou» sem order paga

**Lente:** AV2  
**Actor:** helper JWT (perms só `can_manage_chat`)  
**Pre:** helper aceite/activo; item live_only **sem** order paga; `purchase_broadcast` no mesmo item → `false`.  
**Repro:** `POST /rest/v1/rpc/batata_live_system_message` `{p_live_id, p_body: "✅ RTAV-P2-FOMO comprou …", p_sender_label: "FOMO"}`.  
**Esperado (dinheiro):** anúncio de compra só via `batata_live_purchase_broadcast` com order paga.  
**Obtido:** `200 {"ok": true}`; row `live_messages` `kind=system` id `966acaba-663c-4686-b5e8-568047921474` body exactamente o FOMO. Seller JWT consegue o mesmo (nota pass2). Buyer JWT e seller2 → `not_allowed`. INSERT REST `kind=system` → RLS 403.  
**Porquê P3:** RPC é **staff/seller chat** por desenho (não é o broadcast de compra). Não altera stock, wallet, orders nem Hub. Espectador pode **ver** texto igual ao anúncio de compra. Não é bypass do fecho ANAS em `purchase_broadcast`.  
**Prova:** `pass2.json` finding AV2-05.

### AV-P3-02 — Seller reabre live `ended` e accept pending antigo

**Lente:** AV6  
**Actor:** seller JWT (dono)  
**Pre:** pending criado com live no ar; depois `status=ended` `is_active=false`; UPDATE/RPC accept **enquanto ended** → `live_ended` (AV6-01/02).  
**Repro:** `PATCH lives status=live, is_active=true` + `batata_process_live_reservation_request accept`.  
**Esperado:** fila morta após ended, ou reopen só com Mux real.  
**Obtido:** `200 {"ok": true, … "item_status": "reserved_full"}`; reserva `7066fd6e-…` `status=accepted`.  
**Porquê P3:** só o **dono** reabre a própria live (buyer/seller2 PATCH lives → `permission denied`). Race micro end∥accept **não** deixou accepted em ended (AV6-04). Comportamento de «retomar directo» + reviver fila; sem dinheiro.  
**Prova:** `pass1.json` finding AV6-03.

--------------------------------------------------
## REFUTADOS (não contar)
--------------------------------------------------

- **AV2-11** pass1 `200 []` PATCH `live_messages` kind=system — 0 rows. Pass2 GET: `kind` permanece `chat`. **Não é finding.**
- **AV3-02** Hub «sold» — `mark_sold` sem PI devolve `ok` mas `batata_recompute_live_item_status` **reverte** `status=available` `quantity=1`. Vitrine mostra artigo **ainda à venda**, não um sold. **Não é leak de esgotado.** Pass1 AV3-01 (paused) e AV3-03 (ended) já saturam a lente: anon stock `live_item_not_found`.

--------------------------------------------------
## MATRIZ POR LENTE (bloqueados / saturado)
--------------------------------------------------

### AV1 Convert / broadcast bypass
- Convert sem PI / cancelado+PI / PI noutro `live_item` / PATCH converted / INSERT converted → `convert_requires_paid_order` ou RLS.
- Broadcast cancelado+PI, outro item sem pago, `live_id` mismatch, buyer spoof B2 → `false`.
- Convert após ended **com** PI falhou neste fixture (`order_live_item_product_missing` em live_only) — ainda `convert_requires_paid_order`.

### AV2 Staff / helper / prova social
- Helper chat: mark_sold / accept / convert / broadcast sem pago → `not_allowed` / `false`.
- Escalate PATCH `seller_helpers` → `200 []`.
- Buyer/seller2 `system_message` → `not_allowed`.
- INSERT REST system → 403 RLS.
- PATCH chat→system → 0 rows.

### AV3 Stock / Hub / REST
- Paused + ended: anon `batata_live_item_stock` → `live_item_not_found`.
- INSERT pending em ended → `live_ended`.

### AV4 mark_sold / hitch
- Hitch SKU próprio sem PI: catálogo **não** deslista (AHAM).
- Hitch `checkout_product` / `product_id` seller2 → mismatch.
- Buyer / seller2 mark_sold → `not_allowed`.
- INSERT `status=sold` JWT → `live_item_status_sold_rpc_only`.

### AV5 live_id / qty / cross-seller
- Qty live_only 99 → `live_item_qty_increase_not_allowed`.
- Mover item com reservas para live S2 → `live_item_not_authorized`.
- Reserva `live_id` ≠ item.live_id → `live_item_live_mismatch`.

### AV6 Race
- UPDATE/RPC accept pós-ended → `live_ended`.
- Future.wait end∥accept → `live_ended` (não ficou accepted em ended).
- qty=1 duas accepts → nAcc=1.

### AV7 Sabotar live / Mux
- `complete-mux-live` buyer/seller2 → 403.
- `create-mux-live` buyer → 403.
- `livekit-mux-publish` token seller2 → 403.
- Buyer PATCH ended / SELECT stream keys / seller2 ownership → `permission denied for table lives`.

### AV8 Caixa
- INSERT JWT `status=pago` → forçado `reserva_pendente`.
- PATCH pago+PI forjado → `order_money_fields_immutable`.
- Δ wallet buyer/seller/B2/S2 = 0.

--------------------------------------------------
## NÃO CORRIGIR
--------------------------------------------------

Nenhuma alteração de SQL, RLS, Edge ou `lib/` nesta ronda.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
