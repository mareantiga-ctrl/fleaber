# FROZEN_REPORT — RED TEAM CEGO BE

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 2
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido: NÃO)
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 3
```

**VEREDICTO:** `FAIL_P1`

```
AUDITOR: REDTEAM_BLIND_BE_DISPUTA_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:22:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BE1, BE2, BE3, BE4, BE5, BE6, BE7, BE8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢; `refund-order` executou refund TEST real `re_3UBFto…` / `re_3UBFx7…` / `re_3UBFuB…`) · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Prefixo `RTBE-20260902T1607-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

AY **não lido**. Variantes novas face a AS/AM (não `cancelado` clássico, não `pago`→`concluido`, não `javascript:` em `proof_photos`, não S1 a ler provas B2–S2).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO (refund Stripe = estorno da captura; release JWT com disputa aberta = `false`; Δseller 0→29 **não** atribuído a esta ronda — BD/AX em paralelo no mesmo vendedor)
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 2
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (`order_money_fields_immutable` em qty)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (falsifica **estado de devolução**, não a captura)
12. JWT cria saldo/fundos — NÃO COMPROVADO nesta ronda
13. Refund excede captura — NÃO (`amount` no body ignorado; 590¢)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO (`wallet_*_processed_at` selados em `devolvida` sem crédito JWT visível; buyer 61,10 € inalterado)
15. Payout duplica Transfer — NÃO (fora de poço)
16. Stock=1 duas vendas válidas — NÃO como exploit (2.ª Session só **depois** de refund Stripe real)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (stock preso até `stripe_refund_id`; em n1 preso para sempre)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (S1 GET prova B2–S2 → 404)
21. Buyer assume seller/admin — NÃO (RPC admin 404; oferta seller não persiste)
22. Seller assume buyer/admin — NÃO em disputa `resolvida`; SIM no FSM de **devolução** (hops que são do comprador)
23. Reviews forjadas — NÃO
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_process_partial_refund_dispute` seller `not_allowed`; buyer `dispute_partial_refund_requires_stripe`)
25. RLS crítico quebrado — NÃO (INSERT disputa pago/enviado/B2 403; o buraco é o **guard FSM**, não a policy de SELECT)
26. Edge confia total do cliente — NÃO (`refund-order` seller-only; `amount` cliente ignorado; gate `enviado`/`devolucao_entregue` 403)
27. Regressão funcional (happy path partido) — SIM (resposta Edge `status=cancelado` com BD `devolvida`)
28. Saturação atingida — NÃO (classe nova de hop skip para `devolucao_entregue` / hostage em pago)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Exactos AS/AY/AM da lista — **não redescobertos** como findings.

| Clássico | Resultado |
|----------|-----------|
| seller `devolvida` → stock restore sem refund (AM3) | BLOCKED — `stock_units_applied` só some com `stripe_refund_id` |
| refund blocked shipped on `devolvida` (AM4) | FECHADO — `refund-order` 200 em `devolvida` |
| S1 lê provas disputa B1–S2 (AM7) | BLOCKED — S1 404 no path B2–S2 |
| `proof_photos` javascript: / mailto: / `%2e%2e` | BLOCKED `dispute_proof_url_denied` |
| INSERT disputa `resolvida` | INSERT força/`aberta`; 2.ª disputa `dispute_already_exists_for_order` |
| seller PATCH disputa `resolvida` clássico | BLOCKED — status fica `aberta` |
| `pago`→`concluido` directo sem enviado | BLOCKED `order_concluido_requires_shipped` (mão congelada pós-pago) |
| OCR kick 1442 | não exercido |
| `cancelado` / `canceled` / `cancelada` / NBSP | BLOCKED `orders_status_batata_check` |

Atrofia da lista: **0**. Não `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### P1-BE3/BE8 — Comprador finge `devolucao_entregue`; vendedor um clique `devolvida` + refund + stock (artigo fica com o comprador)

**Lentes:** BE3, BE1, BE4, BE8

**O que isto é:** Depois de pago e enviado, o comprador confirma `entregue` e abre disputa (RLS OK). O guard ANAS impede `devolvida` se o estado anterior não for `devolucao_entregue`, e impede o comprador de marcar `devolvida`. **Não impede** o comprador de saltar `pedido_devolucao` e marcar ele próprio `em_devolucao` e `devolucao_entregue`. O vendedor vê o estado «devolução entregue» e `PATCH devolvida` (200). `refund-order` devolve o PI TEST (590¢) e o stock volta (qty 0→1). O artigo físico nunca foi reenviado — ficou com o comprador.

**Actor:** B1 JWT (hops) · S1 JWT (`devolvida` + `refund-order`)

**Pré:** `setup_paid_order` Stripe TEST → `pago` 590¢ → S1 `enviado` → B1 `entregue` → disputa 201.

**Repro (REST, Flutter não é fronteira):**
1. B1 `PATCH orders.status=em_devolucao` (salta `pedido_devolucao`)
2. B1 `PATCH orders.status=devolucao_entregue`
3. S1 `PATCH orders.status=devolvida`
4. S1 `POST refund-order`

**Esperado:** só o vendedor avança hops de devolução; `devolucao_entregue` exige envio de retorno real; B1 não marca «recebido de volta».

**Obtido:**
- pass1 `fbd46089-…` — Edge `refund-order` já lia `status=devolucao_entregue` (gate `order_refund_blocked_shipped`)
- pass2 confirma BD `devolucao_entregue` → S1 `devolvida` 200 → refund `re_3UBFtoH7FWYUN3jh1DxtHToA`, stock `applied` null, qty produto 1, BD permanece `devolvida`
- reprodução n3 `600c31a8-…`: B1 `entregue`→`em_devolucao`→`devolucao_entregue`; S1 `devolvida`; refund `re_3UBFx7H7FWYUN3jh14dyPYRN`; qty `0→1`

**Porque P1:** caminho explorável para o comprador mentir o hop «retorno recebido». O vendedor não precisa de ser cúmplice consciente — o FSM apresenta o botão seguinte. Dinheiro (estorno Stripe) + stock à venda + bem na mão do comprador. Não é P0: exige o clique `devolvida` do vendedor e o refund é a captura original, não dinheiro inventado.

---

### P1-BE1 — Vendedor (sem disputa) mete `pago` em `devolucao_entregue` e o PI fica refém

**Lentes:** BE1, BE4, BE3

**O que isto é:** O cancelamento pós-pago (`cancelado`/`cancelled`/grafias) está fechado pelo check `orders_status_batata_check` + `order_cancel_denied_post_pay`. O seller JWT ainda pode `PATCH em_devolucao` e `PATCH devolucao_entregue` **a partir de `pago`**, sem envio, sem disputa. `devolvida` exige disputa (`order_devolvida_requires_dispute` 403). INSERT disputa só em `entregue`/`concluido`. `refund-order` bloqueia `devolucao_entregue`. Resultado: captura Stripe viva, stock aplicado, **sem envio, sem reembolso, sem fecho**.

**Actor:** S1 JWT

**Pré:** `setup_paid_order` → `pago`, `shipped_at` null, 590¢.

**Repro:**
1. S1 `PATCH status=em_devolucao`
2. S1 `PATCH status=devolucao_entregue`
3. S1 `PATCH status=devolvida` → 403 `order_devolvida_requires_dispute`
4. (comprador não consegue abrir disputa neste estado)

**Obtido:** n1 `916cac96-…` fica `devolucao_entregue`, `refund=null`, `applied=1`, `qty_prod=0`, `shipped_at=null`, `order_disputes=[]`.

**Porque P1:** o vendedor trava o dinheiro do comprador num estado de «retorno entregue» que nunca existiu. Não é o exacto cancel pós-pago (essa string está fechada) — usa o FSM de devolução como atalho.

---

### P2-BE8 — `refund-order` responde `status=cancelado` com a encomenda `devolvida` na BD

**Lentes:** BE8, BE4

**O que isto é:** ANAS promete terminal `devolvida` no refund. A BD cumpre (`p2`, `n3`, `p8` ficam `devolvida` + `stripe_refund_id`). O JSON do Edge diz `"status":"cancelado"` e `"already_refunded":true` no mesmo pedido. UI/cliente que confie na resposta mente o estado.

**Actor:** S1 `POST refund-order`

**Obtido:** p8 `17b4d90a-…` BD `devolvida` + `re_3UBFuBH7FWYUN3jh1kIj7pgS`; resposta Edge `status=cancelado`. Idem p2/n3.

**Porque P2:** hygiene / mentira de contrato API. Stock e PI batem certo na BD.

--------------------------------------------------
## LENTES — o que foi tentado e fechado
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| BE1 disputa vs FSM | INSERT pago/enviado/B2/S1 403; 2.ª disputa 409; `resolved` EN 23514; admin RPC 404; **aberto:** hops `em_devolucao`/`devolucao_entregue` |
| BE2 enviado ∥ disputa | S1 `enviado` 200; disputa em enviado 403; unship `order_shipped_at_immutable` |
| BE3 devolução / stock | qty 9 `order_money_fields_immutable`; `product_id` revertido; **aberto:** skip hops B1 + hostage S1 |
| BE4 refund no caos | buyer/B2 `Sem permissão`; enviado 403 `order_refund_blocked_shipped`; amount override ignorado; oferta B1 não persiste; RPC parcial exige Stripe / `not_allowed` |
| BE5 receção ∩ disputa | `concluido` com disputa aberta **persiste** (fluxo de «recebi mas está danificado» — não contado); release `false`; `completed_at` não auditado com orderRow no pass1; mão `order_shipping_frozen_after_payment` |
| BE6 etiqueta / carrier | `tracking_code` coluna inexistente; `shipping_method` congelado pós-pago |
| BE7 prova | upload path com `order_id` 200; `../` 403; S2 plant 403; S2/B2 GET 404; mailto/`%2e%2e` denied; `return_label_url` javascript: `order_dispute_label_url_denied`; prefixo sem slash legível só pelo vendedor da encomenda |
| BE8 composição | hops honestos p8 → `devolvida` + refund TEST + stock 1→2 + 2.ª Session 200 (caminho feliz pós-refund); **aberto:** composição do skip B1 |

--------------------------------------------------
## TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------

1. ≥1 order Stripe TEST paga: SIM (`setup_paid_order` × pass1+pass2, PI `succeeded` 590¢)
2. Percorrer envio → disputa → devolução: SIM (p2, n3, p8; ≥2 estados)
3. Contabilidade wallets + stock + status: SIM (buyer 61,10 € estável; stock 0→1 após refund; seller 0→29 **não atribuído** — ronda BD/AX paralela no mesmo perfil)
4. Flutter ≠ fronteira: SIM (REST + Edge)

--------------------------------------------------
## NÃO-FINDINGS (descartados)
--------------------------------------------------

- `BE1.buyer_devolucao_entregue_from_pago` — falso positivo: o seller já tinha deixado n1 em `devolucao_entregue`.
- `BE5.concluido_with_open_dispute` — estado de negócio válido (recebi, está danificado); release bloqueado.
- Grafias `cancelada`/`canceled`/`anulado`/NBSP/`concluído` — check constraint.
- Path storage `order_id` + sufixo sem slash — S1 (dono) 200; S2 404.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_be_20260902T1607/pass1.dart` + `pass1.json` (orderRow partido no pass1 — coluna `return_delivered_at` inexistente; evidência Edge ainda válida)
- `tool/redteam_blind_be_20260902T1607/pass2.dart` + `pass2.json` (confirmação)
- `tool/redteam_blind_be_20260902T1607/pass3.dart` + `pass3.json` (n1 hostage; ledger table nome errado)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
