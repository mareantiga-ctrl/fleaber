# FROZEN_REPORT — RED TEAM CEGO AY

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 2
P2 aberto: SIM          → quantos: 4
P3 aberto: SIM          → quantos: 1  (fora de âmbito salvo pedido: NÃO — P3 documentado)
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 7
```

**VEREDICTO:** `FAIL_P1`

```
AUDITOR: REDTEAM_BLIND_AY_DISPUTA_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:25:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AY1, AY2, AY3, AY4, AY5, AY6, AY7, AY8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢; Edge `refund-order` refund TEST `re_3UBFy0H7FWYUN3jh1Ho3TQKD`) · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Prefixo `RTAY-20260902T1615-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Sem `STRIPE_SECRET_KEY` `sk_test_` no env local: refund Stripe **directo** no PI (fora da Edge) + release **não** exercido. Cron 48 h não esperado.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 2
5. P2 hygiene encontrado — SIM
6. Quantos P2: 4
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (crédito 5,00 € após `concluido`+release é o caminho feliz do comprador)
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO (`refund-order` em `concluido` → 403 shipped)
15. Payout duplica Transfer — NÃO (fora de poço)
16. Stock=1 duas vendas válidas — NÃO (`product_sold` / `order_hold_exceeds_stock` enquanto captura viva)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (stock preso em `devolvida` até refund Stripe)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO COMPROVADO em bytes (S1 404 na pasta S2); URLs de outra order **persistem** em `proof_photos` / replies (P2)
21. Buyer assume seller/admin — NÃO (`batata_admin_resolve_dispute` → «Apenas administradores»)
22. Seller assume buyer/admin — NÃO em `entregue`/`concluido`; SIM no FSM de **devolução** (hops sem pedido do comprador)
23. Reviews forjadas — NÃO (`batata_generate_auto_feedback` JWT → permission denied; `completed_at` não recuado)
24. RPC SECURITY DEFINER perigoso executável — NÃO (admin / cron / partial seller recusados)
25. RLS crítico quebrado — NÃO (storage disputa com `order_id`: S1 404 / S2 200; raso `order_proofs` 404)
26. Edge confia total do cliente — NÃO (`refund-order` seller-only; webhook sem assinatura 400)
27. Regressão funcional (happy path partido) — NÃO (refund em `devolvida` corre; BD permanece `devolvida`; Edge JSON mente `cancelado` = P3)
28. Saturação atingida — NÃO (sem `sk_test_` local para refund Stripe directo; cron 48 h não esperado)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Exactos AS/AM da lista do prompt — **bloqueados / fechados ANAS**, não redescobertos como findings.

| Clássico AS/AM | Resultado |
|----------------|-----------|
| seller `pago`→`entregue` (AS-P1-02) | BLOCKED `order_seller_cannot_mark_entregue` |
| seller `concluido` + release (AS-P1-05) | BLOCKED `order_seller_cannot_mark_concluido` |
| `order_proofs` raso (AS-P1-07) | BLOCKED — upload raso 200; SELECT S1/S2 404 |
| `devolvida` shortcut `pedido`→`disputa_devolucao_vendedor`→`devolvida` (AS-P2-03) | BLOCKED `order_devolvida_denied` a partir de `em_devolucao` |
| refund→`cancelado` na coluna (AS-P2-04) | FECHADO na BD (`status=devolvida`); Edge JSON ainda diz `cancelado` (P3, não o exacto) |
| `proof_photos` `object/public` (AS-P2-07) | BLOCKED (pass1 sem disputa válida; ANAS deny no código vivo — public não persistiu onde testado) |
| stock `devolvida` sem refund (AM3) | BLOCKED qty 0, `applied=1` |
| `refund-order` shipped em `devolvida` (AM4) | FECHADO — 200 refund Stripe TEST |
| INSERT disputa `resolvida` (AM3-P3) | BLOCKED — 201 com status reescrito (não `resolvida`) |

Atrofia da lista: **0 / 9**. Não `ATROFIA_ABORT`.

Finding AY **não** é o atalho AS-P2-03: ANAS exige `devolucao_entregue` para `devolvida` (403 confirmado). O furo novo é **chegar a `devolucao_entregue` sem `pedido_devolucao`**.

Pass1 `AY4.am4_regress` é **falso**: `orderRow` pedia coluna `return_delivered_at` inexistente em `orders`; o refund foi em `em_devolucao`. Não entra na CONTAGEM.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### P1-AY3 — Seller entra no FSM de devolução sem `pedido_devolucao`

**Lentes:** AY3, AY1, AY8

**O que é:** Depois de pago+enviado+entregue e disputa aberta pelo comprador, o **vendedor JWT** faz `PATCH status=em_devolucao` **sem** o comprador ter passado por `pedido_devolucao`. Persistido. O guard ANAS só exige `devolvida` a partir de `devolucao_entregue`; não exige que o comprador peça a devolução.

**Actor:** seller JWT

**Pré:** `setup_paid_order` Stripe TEST → `pago` 590¢ → `enviado` → `entregue` → `POST order_disputes` 201

**Repro (REST, Flutter não é fronteira):**
1. Seller `PATCH orders status=em_devolucao`

**Esperado:** hop só após `pedido_devolucao` do comprador.

**Obtido:** order `bac537c8-…` status=`em_devolucao` HTTP 200. A partir daí o mesmo seller fez `devolucao_entregue` → `devolvida` (200). Stock preso (qty 0, applied 1). `refund-order` 200, refund Stripe `re_3UBFy0…` 590¢, qty 0→**1**, BD permanece `devolvida`.

**Porque P1:** caminho explorável para o vendedor **iniciar e fechar** a devolução (e reembolsar) sem o comprador ter pedido. Não é o exacto AS-P2-03 (esse atalho `devolvida` a partir de `disputa_devolucao_vendedor` / `em_devolucao` continua 403).

---

### P1-AY3b — Seller `entregue`→`devolucao_entregue` (salta pedido e em_devolucao)

**Lentes:** AY3, AY2

**O que é:** O mesmo denylist: de `entregue` o seller salta **directo** para `devolucao_entregue` (selaria `return_delivered_at` se a coluna existisse em `orders`). Depois `devolvida` é o hop ANAS *legal*.

**Actor:** seller JWT

**Repro:**
1. Cadeia pago→enviado→entregue→disputa
2. Seller `PATCH status=devolucao_entregue`
3. Seller `PATCH status=devolvida`

**Obtido:** `6914c0eb-…` `devolucao_entregue` 200, depois `devolvida` 200. Buyer nunca fez `pedido_devolucao`.

**Porque P1 (separado):** um único PATCH atinge o único estado a partir do qual ANAS *permite* `devolvida`. Compõe com refund-order (já provado na cadeia `bac537c8`).

---

### P2-AY3 — Buyer marca `em_devolucao` a partir de `entregue`

**Lente:** AY3

**O que é:** O comprador JWT, com disputa aberta, faz `PATCH em_devolucao` sem passar por `pedido_devolucao`. Persistido (`000ea5b4-…`).

**Porque P2:** FSM; não restaura stock nem minta captura. `devolvida` continua seller-only.

---

### P2-AY6 — `return_label_url` aceita path `sign/fleaber_private` alheio

**Lente:** AY6

**O que é:** Seller PATCH `return_label_url` =
`https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/dead/label.pdf`
→ 200, persistido na disputa `5478eb21-…` (order `f3274d36-…`).

**Esperado:** só etiqueta da encomenda / carrier.

**Porque P2:** phishing de etiqueta; não é dinheiro.

---

### P2-AY7 — `proof_photos` aceita URL authenticated de **outra** encomenda

**Lente:** AY7

**O que é:** O trigger ANAS exige `sign|authenticated/fleaber_private` e bloqueia `public/`. **Não** amarrou `order_id` da disputa. Buyer PATCH na disputa S1 (`53dc2950-…` / order `5b5bf255-…`) com URL
`…/authenticated/fleaber_private/order_disputes/{B1}/{oidS2}/x.png` → persistido.

**Esperado:** path só desta `order_id`.

**Porque P2:** a UI pode mostrar prova alheia; o GET storage de S1 na pasta S2 continua 404 (RLS OK). Não é o exacto AM7/AS-P1-07.

---

### P2-AY7b — Reply `proof_photos` com URL authenticated de outra order

**Lente:** AY7

**O que é:** `POST order_dispute_replies` 201 (`882c45ef-…`) com a mesma classe de URL (pasta S2) na disputa S1.

**Porque P2:** paridade com AY7; replies tinham deny `javascript:` (AS) mas não bind de `order_id`.

---

### P3-AY4 — Edge `refund-order` JSON `status=cancelado` enquanto a BD fica `devolvida`

**Lente:** AY4

**O que é:** ANAS manteve o terminal na coluna (`bac537c8-…` `status=devolvida` após refund, qty 1, `re_3UBFy0…`). A resposta da Edge diz `"status":"cancelado","already_refunded":true` no mesmo pedido (e no 2.º, idempotente, qty continua 1).

**Porque P3:** ledger Stripe/stock/BD coerentes com devolução; o cliente que confiar no JSON da Edge vê cancelamento. Não é o exacto AS-P2-04 (coluna já não muda).

--------------------------------------------------
## BLOQUEADO (defesa a funcionar / ANAS)
--------------------------------------------------

- JWT alheio / seller / anon insert disputa · disputa em `pago` e `enviado`
- Buyer `entregue` sem `enviado` → `order_entregue_requires_enviado`
- Buyer `pago`→`concluido` carrier → `order_concluido_requires_shipped`
- Seller `enviado`→`entregue` → `order_seller_cannot_mark_entregue`
- Seller `concluido` → `order_seller_cannot_mark_concluido`
- Buyer `pedido_devolucao` sem disputa → `order_pedido_devolucao_requires_dispute`
- Buyer `concluido` em FSM de devolução → `order_concluido_denied_during_return`
- `devolvida` a partir de `em_devolucao` → `order_devolvida_denied`
- `batata_admin_resolve_dispute` buyer → P0001
- INSERT `resolvida` em `entregue` → 201 reescrito (não persiste `resolvida`)
- `batata_generate_auto_feedback` JWT → permission denied
- Fake `stripe_refund_id` → `order_money_fields_immutable`
- `refund-order` buyer → 403 Sem permissão
- Partial RPC seller → `not_allowed`; buyer pós-envio → `false`
- Release + `refund-order` em `concluido` → 403 `order_refund_blocked_shipped`
- `enviado` sem captura → `order_status_requires_capture`
- `shipping_method` pós-pago → `order_shipping_frozen_after_payment`
- AM3 stock em `devolvida` sem refund: qty 0 applied 1; hold B2 `order_hold_exceeds_stock`; `available=0` `product_sold`
- AM7 disputa path com `order_id`: S1 404 / S2 200
- Shallow `order_proofs/{B1}/ficheiro`: S1/S2 404
- Prefix `order_disputes/{B1}/{oidS2}-extra`: S1 404 / S2 200 (UUID)
- B2 write pasta B1 → 403
- `stripe-webhook` sem assinatura → 400 `missing_signature`
- 2.º `refund-order` idempotente, qty não duplica

Buyer `enviado`→`concluido`+release (+5,00 €) + disputa 403: **design** (comprador confirma receção e sela o slot). Não finding. Relógio `completed_at` arranca; cron 48 h JWT-inacessível.

--------------------------------------------------
## CONTABILIDADE (amostras)
--------------------------------------------------

| Sítio | Antes | Depois |
|-------|--------|--------|
| `bac537c8-…` cadeia | `pago` 590¢ applied 1 | seller skip → `devolvida` qty **0** applied 1 PI vivo → refund `re_3UBFy0…` qty **1** BD `devolvida` |
| `6914c0eb-…` atalho | `entregue`+disputa | `devolucao_entregue`→`devolvida` sem `pedido_devolucao` |
| `02679af3-…` | `enviado` | `concluido` + release **true** Δseller **+5,00 €** (feliz) |
| B2 no SKU `01331e9d-…` em `devolvida` sem refund | — | `available=0` `product_sold`; hold 400 |

Wallets: crédito só no release feliz do comprador. Refund Stripe 590¢ na cadeia de devolução. Sem mint extra.

--------------------------------------------------
## TÁCTICAS
--------------------------------------------------

1. ≥1 order Stripe TEST paga: SIM (PI `succeeded` 590¢ × várias)
2. Envio → disputa → devolução: SIM (`enviado` → `entregue` → disputa → `em_devolucao` / `devolucao_entregue` → `devolvida` → refund)
3. Contabilidade wallets + stock + status: SIM
4. Flutter ≠ fronteira: SIM (REST/Edge/RPC/Storage)

Lentes AY1–AY8 cobertas (8/8).
