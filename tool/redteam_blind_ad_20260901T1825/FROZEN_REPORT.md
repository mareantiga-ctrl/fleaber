AUDITOR: REDTEAM_BLIND_AD_POS_YZAA_v1
FROZEN_AT: 2026-09-01T18:50:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AD1, AD2, AD3, AD4, AD5, AD6, AD7, AD8]
VEREDICTO: FAIL_P1

Prefixo: `RTAD-20260901T1825`
Staging: `fxdknzrqjenzqcvnwqqq`
Stripe TEST: não usado
service_role: só fixture (lives/products/users)
Lives de teste: `ended` + `is_active=false` no `finally`

Poço: Facebook/manual/staff ainda consome stock sem dinheiro — **SIM (P1)**.
Não é PATCH pending→converted exact, nem helper PATCH pending→converted exact, nem qty+converted exact, nem Hub `hub_live_items_public` exact.

---

## CONTAGEM

```
P0 aberto: NÃO         → quantos: 0
P1 aberto: SIM         → quantos: 3
P2 aberto: SIM         → quantos: 2
P3 aberto: SIM         → quantos: 4
```

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 3
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 4
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (INSERT order `pago` recusado / money cols)
12. JWT cria saldo/fundos — NÃO (Δ wallet = 0)
13. Refund excede captura — NÃO COMPROVADO (fora de âmbito live AD)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO (race accept não oversell)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — SIM (`converted` sem order paga)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO
24. RPC SECURITY DEFINER perigoso executável — NÃO (`stripe_convert` 403 grant; `mark_sold` alheio `not_allowed`)
25. RLS crítico quebrado — NÃO (seller2/helper foreign recusados)
26. Edge confia total do cliente — NÃO COMPROVADO (`create-live-checkout` 404 nesta staging)
27. Regressão funcional (happy path partido) — NÃO COMPROVADO (accept legítimo + RPC convert com PI não exercitado ponta-a-ponta)
28. Saturação atingida — NÃO (P1 aberto; controlos AA pending→converted e INSERT facebook converted continuam fechados)

---

## FINDINGS P1

### RTAD-AD1-patch-accepted-converted-iso · P1 · AD1 · seller

**Repro:** item live_only qty=1 → INSERT `facebook_manual` pending → RPC `accept` → PATCH `live_reservation_requests.status=converted` JWT seller. Zero order / PI.

**Impacto:** `sold_converted_qty` 0→1, `available_qty` 1→0, `hub_live_items_public` some, `orders=[]`. `processed_by_user_id` = seller.

**Porquê novo:** o fecho PATCH converted só corre quando o estado *anterior não consome* capacidade. `accepted` já consome → o teste de order paga é saltado. Controlo: PATCH `pending→converted` continua `403 convert_requires_paid_order`. RPC `convert` sem PI continua `ok:false convert_requires_paid_order`.

**Prova:** `findings_pass2.json` `RTAD-AD1-patch-accepted-converted-iso`  
request `674d46fc-e098-48e6-ae24-ddadfad08438`

---

### RTAD-AD2-helper-patch-accepted-converted-iso · P1 · AD2 · helper

**Repro:** mesmo caminho JWT helper (`can_manage_reservations`). INSERT facebook_manual → RPC accept → PATCH converted.

**Impacto:** `status=converted`, `sold_converted_qty=1`, `orders=0`. Staff/Facebook-ops consome stock sem dinheiro.

**Porquê novo:** não é helper PATCH pending→converted (isso está fechado: pass1 helper pending/accepted mismatch deu 403). É accepted→converted.

**Prova:** `findings_pass2.json` `RTAD-AD2-helper-patch-accepted-converted-iso`  
request `991c3dab-5907-465c-80ca-911aa13450c8`

---

### RTAD-AD1-insert-fleaber-converted-p3 · P1 · AD1 · seller

**Repro:** JWT seller `POST live_reservation_requests` `source=fleaber_live` `status=converted` `buyer_id=<seller>`. RLS permite porque `fleaber_live` + `auth.uid()=buyer_id`. Trigger `force_pending_manual` só cobre `facebook_manual`/`helper_manual`. Guard INSERT seller **não** exige order paga.

**Impacto:** 201; `status=converted`; stock `available` 2→1, `sold_converted` 0→1; `orders=0`; `processed_by_user_id=null`. Hub público ainda mostra o item (qty restante >0).

**Controlo:** INSERT `facebook_manual` converted → forçado `pending`. Buyer INSERT `fleaber_live` converted → forçado `pending`.

**Prova:** `findings_pass3.json` + pass1 `63fb5a02-7ee9-4693-a16e-6ce71a3dec08`  
request p3 `b6b82b38-83f3-4773-a636-b85ef3581665` item `04f8d5e8-1ad0-4d10-a7a3-eb195b673cc3`

---

## FINDINGS P2

### RTAD-AD3-discovery-shows-exhausted · P2 · AD3 · buyer

**Repro:** facebook_manual accept qty=1 em item qty=1 (sem convert).

**Obtido:** `batata_live_item_stock.available_qty=0`; `hub_live_items_public` vazio (filtro YZAA ok); `hub_live_items_discovery_public` **ainda devolve** o item `status=reserved_full`.

A view discovery **não** tem `available_qty>0` nem `quantity>0`. Hub «fantasma» no feed discovery.

**Prova:** pass1 item `53f31415-b4f9-406e-a4d5-d484b253c303`

---

### RTAD-AD3-patch-status-sold-hub-iso · P2 · AD3 · seller

**Repro:** PATCH `live_items.status=sold` JWT dono, zero reservas/PI.

**Obtido:** Hub público some; discovery some; stock RPC continua `available=1` `sold=0`. Não consome unidades convertidas — esconde a montra. `mark_sold` RPC neste estado **não** persiste sold (recompute). Este PATCH fura a paridade.

**Prova:** pass2 item `2da24cc0-0284-42b7-bcd0-0ec302280ff9`

---

## FINDINGS P3

### RTAD-AD3-live-items-rest-exhausted · P3 · AD3

GET `live_items` JWT buyer ainda devolve item `reserved_full` com available=0. Necessário ao player; não é o mesmo buraco que discovery.

### RTAD-AD4-patch-product-unlist · P3 · AD4

Seller PATCH `products.is_sold=true` + `list_on_marketplace=false` no SKU próprio. Dono a gerir a loja — não é `mark_sold` sem PI. `hub_products_public` some. Fora do poço «stock sem dinheiro».

### RTAD-AD5-move-live-id-no-reservation · P3 · AD5

`live_id` mutável **até existir 1 reserva** (fecho YZAA: imutável *se* houve reserva). Cross-seller recusado `live_item_not_authorized`. PATCH reserva.live_id recusado `live_item_live_mismatch`.

### RTAD-AD5-helper-mark-inflate-qty · P3 · AD5

Helper **com** `can_mark_items_sold` (concedido pelo dono) PATCH `quantity` 1→40. Sem essa perm: `live_item_qty_increase_not_allowed`. Acoplamento da perm, não bypass unauth. View-only inflate recusado.

---

## BLOQUEADO (saturação parcial — não atrofia)

| ID | Lente | Resultado |
|----|--------|-----------|
| PATCH pending→converted | AD1 | 403 `convert_requires_paid_order` |
| INSERT facebook_manual converted | AD1 | forçado `pending` |
| RPC process convert sem PI | AD1 | `convert_requires_paid_order` |
| `batata_live_reservation_stripe_convert` JWT | AD1 | 403 permission denied (seller/buyer/helper) |
| INSERT order `pago` JWT | AD1 | 400 / money cols |
| helper self-escalate perms | AD2 | permissions inalteradas |
| view-only accept/convert/mark_sold/qty | AD2 | `not_allowed` / `live_item_not_authorized` |
| mark_sold live_only persiste sold | AD4 | RPC `ok:true` mas recompute deixa `available`; Hub continua visível |
| mark_sold mkt unlist SKU | AD4 | `is_sold=false` `list_on_marketplace=true` |
| race 2× accept qty=1 | AD6 | sem oversell (`live_item_qty_below_reservations` / 0 accepted) |
| seller2 accept/PATCH/mark_sold alheio | AD7 | `not_allowed` / PATCH `200 []` |
| helper mark_sold item seller2 | AD7 | `not_allowed` |
| seller1 inflate qty seller2 | AD7 | `not_allowed` |
| Δ wallet | AD8 | 0 (buyer 61.1 / seller 18.97 inalterados) |

Anti-atrofia: caminhos **novos** ≥50%. Não se parou nos exactos AA1/AA2/AA3/hub listing/mark_sold mkt/live_id-com-reservas.

---

## NOTAS

- `processed_by_user_id` gravado no PATCH converted; **null** no INSERT fleaber converted.
- `mark_sold` sem PI **não** deslista marketplace e **não** deixa `live_items.status=sold` (recompute). O RPC devolve `ok:true` na mesma — ruído, não consumo de stock.
- Happy path não partido nos controlos: accept RPC facebook_manual funciona; convert RPC recusa sem PI.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
