# FROZEN_REPORT — RED TEAM CEGO AM

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 3
P2 aberto: SIM          → quantos: 1
P3 aberto: SIM          → quantos: 1  (fora de âmbito salvo pedido: NÃO — P3 documentado)
P4 aberto: NÃO          → quantos: 0
```

**VEREDICTO:** `FAIL_P1`

```
AUDITOR: REDTEAM_BLIND_AM_DISPUTA_POS_AEAFAG_v1
FROZEN_AT: 2026-09-02T07:45:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AM1, AM2, AM3, AM4, AM5, AM6, AM7, AM8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢; 2.ª Session Checkout criada, captura 4242 **não** feita — sem `sk_test_` local) · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação / cleanup. Prefixo `RTAM-20260902T0730-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 3
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (o crédito 5,00 € em `concluido`+`resolvida` é o release feliz, não mint extra)
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de poço)
16. Stock=1 duas vendas válidas — SIM (2.º hold/checkout no mesmo SKU após restore)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO (Session TEST criada; sem `sk_test_` local para confirmar PI)
18. Bypass capacidade/reserva — SIM (restore em `devolvida` sem refund da 1.ª captura)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — SIM (provas de disputa B1–S2 lidas por S1)
21. Buyer assume seller/admin — NÃO (`batata_admin_resolve_dispute` → «Apenas administradores»)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de poço)
24. RPC SECURITY DEFINER perigoso executável — NÃO (admin resolve recusado; partial refund seller `not_allowed`; wallet refund buyer `false` após selo)
25. RLS crítico quebrado — NÃO (insert disputa alheia 403; storage hijack 403)
26. Edge confia total do cliente — NÃO (`refund-order` seller-only; gate shipped/disputa)
27. Regressão funcional (happy path partido) — SIM (seller **não consegue** `refund-order` após `devolvida` se `shipped_at` está selado)
28. Saturação atingida — NÃO (2.ª captura Stripe não clicada; race HTTP paralelo enviado∥disputa não feito)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Probes da lista clássica: **bloqueados** (não redescobertos como findings).

| Clássico | Resultado |
|----------|-----------|
| dual Session | não exercido neste poço (checkout AM) |
| seguro plain | n/a |
| seller PATCH disputa `resolvida` | BLOCKED — status permanece `aberta` |
| pago→concluido carrier sem enviado | BLOCKED `order_concluido_requires_shipped` |
| PATCH `shipping_method=mão` pós-pago | BLOCKED `order_shipping_frozen_after_payment` |
| OCR kick 1442 | fora de poço |
| cancel pós-pago | `refund-order` em enviado/concluido/devolvida → 403 shipped |

Atrofia da lista: **0 / 6**. Não `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### P1-AM3/AM8 — Seller força `devolvida` sem prova: stock volta, 1.ª captura viva, 2.º checkout

**Lentes:** AM3, AM8 (composição caixa)

**O que é:** Depois de pago+enviado, o comprador abre disputa e passa a `pedido_devolucao`. O **vendedor JWT**, sem etiqueta, sem `return_delivered_at`, sem refund, faz `em_devolucao` → `devolucao_entregue` → `devolvida`. O trigger de stock trata `devolvida` como cancelamento: `quantity` 0→1, `stock_units_applied` limpo, `is_sold=false`, `list_on_marketplace=true`. O PI Stripe da 1.ª venda continua `amount_paid_cents=590` sem `stripe_refund_id`. Um 2.º comprador cria order no mesmo `product_id` e a Edge `create-payment-intent` devolve Checkout Session TEST.

**Actor:** seller JWT (hops) · buyer2 JWT (2.º checkout)

**Pré:** `setup_paid_order` Stripe TEST → `pago`, qty produto 1, applied 1.

**Repro (REST, Flutter não é fronteira):**
1. Seller `PATCH status=enviado`
2. Buyer `PATCH status=entregue` · `POST order_disputes` · `PATCH status=pedido_devolucao`
3. Seller `PATCH em_devolucao` · `devolucao_entregue` · `devolvida`
4. B2 `POST orders` + `create-payment-intent` no mesmo SKU

**Esperado:** hops de devolução exigem prova / etiqueta / receção; stock permanece claimado até refund Stripe; `available=0` enquanto a 1.ª captura existir.

**Obtido (pass1 `34cd2e46-…` / pass2 `e775d91d-…`):**
- `status=devolvida`, `qty` 0→1, `applied` 1→null
- `pi_3UB7rXH7FWYUN3jh1C1ioulJ` capturado, `stripe_refund_id` null
- Δwallet comprador 0 (não mintou)
- `batata_product_checkout_available` → `{ok:true, stock:1, available:1, held:0}`
- Session `cs_test_a1aGvbUPSg5U4DFt4v8cd8R29dayNzwjXaoc57JPo0AtYmGi5IwBROmGDS` (200)

**Caixa:** 1.ª captura 5,90 € na plataforma, sem reembolso JWT. 2.ª Session no montante do catálogo. Captura líquida da 2.ª **NÃO COMPROVADA** (sem `sk_test_` neste harness). Não é P0.

**Porque P1:** caminho explorável de oversell / artigo fantasma. P0 exigiria 2.ª captura permanente.

---

### P1-AM4 — `refund-order` após `devolvida` bloqueado por `shipped_at`; via wallet selada

**Lente:** AM4

**O que é:** No hop para `devolvida`, o trigger chama `batata_refund_buyer_wallet_for_order`. Como o pagamento é plataforma capturada **sem** refund Stripe, a função **não** credita a carteira do comprador (correcto) mas **sela** `wallet_refund_processed_at` + `wallet_release_processed_at`. O comentário interno diz que o buyer recupera via Edge `refund-order`. Essa Edge consulta `batata_order_allows_seller_stripe_refund`, que recusa **primeiro** se `shipped_at IS NOT NULL` — o ramo terminal `devolvida → ok:true` **nunca corre**. Resultado: 403 `order_refund_blocked_shipped` com `status=devolvida`. RPC wallet a seguir → `false`. Comprador sem via JWT (Stripe nem carteira).

**Actor:** seller JWT (`refund-order`) · buyer JWT (RPC wallet)

**Repro:** cadeia AM3 até `devolvida` (com `shipped_at` do enviado) → `POST refund-order` → `rpc batata_refund_buyer_wallet_for_order`

**Esperado:** em `devolvida`, refund Stripe residual permitido (ou wallet se essa for a política); `shipped_at` não anula o terminal de devolução.

**Obtido:**
```
403 {"ok":false,"error":"Não é possível anular esta venda neste estado (já enviada ou concluída).",
     "code":"order_refund_blocked_shipped","status":"devolvida"}
rpc wallet: 200 false · Δbuyer=0
```
PI `pi_3UB7rXH7FWYUN3jh1C1ioulJ` · `amount_paid_cents=590` · flags wallet seladas `2026-09-02T06:41:38.749377Z`

**Impacto:** dinheiro da 1.ª captura fica na plataforma; suporte/Stripe dashboard seria a única via. Regressão do happy path «devolvida → reembolsar». Encadeia com P1-AM3 (seller restaura stock **e** fecha a porta de refund).

---

### P1-AM7 — Seller S1 lê provas de disputa de uma encomenda B1–S2

**Lente:** AM7

**O que é:** Política `fleaber_private_select_order_counterparty`: o vendedor lê `order_disputes/{buyer_id}/%` se **qualquer** order existir com esse buyer — **não** restringe ao `order_id` da disputa. S1 (outra venda com B1) descarrega o PNG que B1 carregou na disputa com S2.

**Actor:** seller JWT (S1)

**Pré:** B1–S1 têm histórico; B1–S2 order paga `4b4d6c03-…`; upload `order_disputes/{B1}/{orderS2}-s2-secret.png`

**Repro:** `GET /storage/v1/object/fleaber_private/order_disputes/{B1}/4b4d6c03-…-s2-secret.png` com JWT S1

**Esperado:** 403 — só o vendedor **daquela** encomenda lê as provas.

**Obtido:** S1 **200** `binary:8b` · S2 (legítimo) também 200. Hijack de escrita B2→pasta B1: **403** (escrita OK).

---

### P2-AM7 — `order_disputes.proof_photos` aceita `javascript:` e URL externa

**Lente:** AM7

**O que é:** O trigger `batata_order_dispute_replies_guard_insert` valida URLs **só em replies INSERT**. A tabela `order_disputes.proof_photos` não tem deny equivalente no INSERT nem no UPDATE.

**Actor:** buyer JWT

**Repro:**
- `POST order_disputes` `proof_photos=["javascript:alert(1)","https://evil.example/disp.png"]` → **201** (id `988cd2ef-…`)
- `PATCH order_disputes` as mesmas URLs → **200**, persistido

**Esperado:** `dispute_proof_url_denied` (paridade com replies).

**Obtido:** replies INSERT evil → 403 `dispute_proof_url_denied`; disputa INSERT/PATCH evil → aceite. PATCH de replies → RLS sem UPDATE (200 `[]`).

**Risco:** XSS / phishing se a UI carregar `proof_photos` como URL; não é dinheiro.

---

### P3-AM1 — INSERT disputa com `status=resolvida` (não é P0)

**Lente:** AM1

**O que é:** RLS de insert não força `aberta`. Buyer `POST status=resolvida` → 201, linha fica `resolvida`. `batata_release_seller_wallet_for_order` trata `resolvida` como fechada e **liberta** a venda — o mesmo que `concluido` **sem** disputa. TX `venda` 5,00 € em `626b6ab1-…` (`138bc41f-…`). **Não há mint extra** vs o happy path. O efeito colateral é queimar o slot `insert_once` (já não abre disputa real).

**Não classificado P0.** Higiene FSM. `current_turn` ficou `vendedor` (inconsistente com terminal).

--------------------------------------------------
## BLOQUEADO (defesa a funcionar)
--------------------------------------------------

- JWT alheio / seller / anon insert disputa · disputa em `pago` e em `enviado` · RLS
- `batata_admin_resolve_dispute` buyer → P0001 admin only
- seller fecha `resolvida` · `return_label_url` externa `order_dispute_label_url_denied`
- seller `pedido_devolucao` → `enviado`/`concluido` → `order_return_in_progress`
- `refund-order` em enviado · buyer chama refund-order 403 · partial disputa pós-envio `dispute_partial_refund_requires_stripe` · seller chama partial `not_allowed`
- release com disputa **aberta** → `false`, sem Δ
- buyer `pedido_devolucao` → `concluido` permitido, mas release recusa se disputa aberta
- storage write hijack pasta alheia 403
- B2/S2 SELECT disputa alheia → `[]`

--------------------------------------------------
## CONTABILIDADE (amostra pass2 chain)
--------------------------------------------------

| Sítio | Antes cadeia | Depois `devolvida` |
|-------|----------------|---------------------|
| Order `e775d91d-…` | `pago` · applied 1 · paid 590¢ | `devolvida` · applied null · PI vivo · refund_id null |
| Product `4cc3a5b0-…` | qty 0 | qty 1 · listed · not sold |
| Wallet B1 | 61,10 (pass1 residual) | Δ 0 nesta cadeia |
| Wallet S1 | 21,97 após pass2 start | Δ 0 nesta cadeia (flags seladas sem mint) |
| Stripe | PI 1 succeeded | 2.ª Session criada, não confirmada |

--------------------------------------------------
## TÁCTICAS
--------------------------------------------------

1. ≥1 order Stripe TEST paga: SIM (`setup_paid_order` × várias, PI `succeeded` 590¢)
2. Envio → disputa → devolução: SIM (`enviado` → `entregue` → disputa → `pedido_devolucao` → `devolvida`)
3. Contabilidade wallets + stock + status: SIM
4. Flutter ≠ fronteira: SIM (REST/Edge/RPC/Storage)

Lentes AM1–AM8 cobertas (≥4).
