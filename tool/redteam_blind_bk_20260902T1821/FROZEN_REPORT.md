# FROZEN_REPORT — REDTEAM_BLIND_BK_DISPUTA_POS_ATBE_v1

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 2

AUDITOR: REDTEAM_BLIND_BK_DISPUTA_POS_ATBE_v1
FROZEN_AT: 2026-09-02T17:35:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BK1, BK2, BK3, BK4, BK5, BK6, BK7, BK8]
VEREDICTO: FAIL_P1

Prefixo fixtures: `RTBK-20260902T1821-`
Staging: `fxdknzrqjenzqcvnwqqq`
Stripe: TEST
Actors: anon · buyer JWT · seller JWT · buyer2 · seller2
service_role: só fixture / observação / cleanup

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
9. Buyer manipula preço autoritativo — NÃO (fora do poço disputa)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (release disputa/retorno = `false`; partial RPC 403 Stripe)
13. Refund excede captura — NÃO (Edge sem amount cliente; residual ≤ captura)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (B2/buyer refund-order 403)
20. Cross-user dados sensíveis — NÃO (B2 GET replies 200 []; wrap GET storage 400)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (seller não fecha disputa; não INSERT disputa)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`not_allowed` seller partial; release `false`)
25. RLS crítico quebrado — NÃO (B2 INSERT disputa 403)
26. Edge confia total do cliente — NÃO (refund amount ignorado; só seller)
27. Regressão funcional (happy path partido) — NÃO (`setup_paid_order` + disputa `danificado` + refund pago OK)
28. Saturação atingida — SIM (8/8 lentes; último passe sem classe nova P0/P1)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

Pós-ATBE o hop exacto `pago`→`em_devolucao` (seller) e `devolucao_entregue` (buyer) estão fechados. Edge `refund-order` devolve `status=cancelado` alinhado com a BD.

Fica **aberto um P1 novo**: o seller JWT saltar `pago`→`pedido_devolucao` **sem disputa**. Isso congela o PaymentIntent capturado: o comprador não abre disputa (RLS exige `concluido`/`entregue`), não marca `concluido`, o seller não marca `enviado`, o Edge recusa refund (`order_refund_blocked_status`), o release devolve `false`, `stock_units_applied` permanece 1. O seller continua o FSM até `devolucao_entregue` sozinho; `devolvida` ainda exige disputa.

**P2:** o bind de `proof_photos` / `return_label_url` aceita a needle `order_disputes/{buyer}/{order}` **em qualquer sítio da URL** (query string, path de outra order). Host evil / `javascript:` / wrap `fleaber.app?https` recusados. GET storage do object wrap = 400 (sem ficheiro) — sem loot.

Anti-atrofia: exactos AY/BE **0 de 3** reabertos. Achados = variantes novas pedidas (PI hostage, wrap URL). Não é `ATROFIA_ABORT`.

Pass2 `buyer_concluido_mid_return` foi **falso positivo** (disputa já `recusada` → order ficou `concluido` → PATCH no-op). Pass3 com disputa **aberta** + `pedido_devolucao`: 403 `order_concluido_denied_during_return`. Não conta.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### BK6-01 · P1 · BK1 / BK6 / BK2 — Seller `pago`→`pedido_devolucao` sem disputa (PI hostage)

**Actor:** seller JWT  
**Pré:** order Stripe TEST `pago`, `amount_paid_cents=590`, `stock_units_applied=1`, sem `order_disputes`.  
**Repro:** `PATCH orders status=pedido_devolucao` (JWT seller). Depois buyer `POST order_disputes`, `PATCH concluido`, Edge `refund-order`, RPC `batata_release_seller_wallet_for_order`. Seller `PATCH em_devolucao` → `devolucao_entregue`.

**Esperado:** 403 (só comprador com disputa em `concluido`/`entregue`).  
**Obtido:**

| Passo | Resultado |
|--------|-----------|
| Seller `pedido_devolucao` | 200 persistido · order `00284979-…` e `d2220435-…` |
| Buyer disputa | 403 RLS |
| Buyer `concluido` | 403 `order_concluido_denied_during_return` |
| Seller `enviado` | 403 `order_return_in_progress` |
| Edge `refund-order` | 403 `order_refund_blocked_status` (`pedido_devolucao`) |
| Release wallet | 200 `false` · Δwallet 0 |
| Seller `em_devolucao` | 200 |
| Seller `devolucao_entregue` | 200 · status final `devolucao_entregue` |
| Seller `devolvida` | 403 `order_devolvida_requires_dispute` |
| PI | `pi_3UBI01H7FWYUN3jh1IBcTXcv` captured, `stripe_refund_id` vazio |
| Stock | `stock_units_applied=1`, qty produto não reposta |

**Impacto:** o vendedor trava uma venda paga sem o comprador pedir devolução. O dinheiro fica no Stripe; o produto não segue; o comprador não tem disputa nem refund self-serve. Não é mint (seller também não recebe).  
**Prova:** `pass1.json` BK1.seller_pedido_from_pago · `pass2.json` BK6.pi_hostage_seller_pedido.

---

### BK3-01 · P2 · BK3 — Bind de prova/etiqueta é substring (wrap query / outra order)

**Actor:** buyer JWT  
**Pré:** disputa `aberta` em order concluída.  
**Repro:** `PATCH order_disputes` com  
`https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/order_disputes/{outro_oid}/secret.png?q=order_disputes/{buyer}/{esta_order}`  
nos campos `return_label_url` e `proof_photos`.

**Esperado:** recusa se o **object path** não for `order_disputes/{buyer}/{esta_order}/…`.  
**Obtido:** 200; URL persistida (disputa `5500e018-…` order `dea4d17f-…`; confirmação cruzada orders `ef2e4ecf-…` ← `1146fbe1-…`). Host `evil.example` 403; `javascript:` 400; wrap `fleaber.app?https` 400. GET storage do path wrap: **400** (ficheiro inexistente) — sem leitura de prova alheia nesta ronda. Variante `../order_disputes/…` também persiste (mesma classe).

**Impacto:** a UI/staff pode mostrar etiqueta/prova cujo path é de **outra** encomenda. Sem ficheiro = sem leak demonstrado.  
**Prova:** `pass2.json` BK3.label_wrap_storage_other / photos_wrap · `pass3.json` BK3.wrap_bind_substring (GET 400/400).

--------------------------------------------------
## LENTES (8/8)
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| BK1 pedido_devolucao | P1 seller from `pago` sem disputa. Buyer from `pago` 403 `order_pedido_devolucao_denied`. Buyer `concluido` sem disputa 403 `order_pedido_devolucao_requires_dispute`. |
| BK2 hops FSM | Exactos AY/BE fechados. Seller `devolvida` from `pago` 403. Seller sozinho até `devolucao_entregue`. Buyer `concluido` mid-return (disputa aberta) 403. Race `enviado`∥`concluido`: buyer ganhou `concluido`; seller 403 immutable. |
| BK3 provas/URLs | P2 wrap substring. Replies PATCH wrap/`javascript:` 200 [] (sem UPDATE). INSERT reply OK. |
| BK4 refund/Edge | Buyer/B2 403. Partial RPC `concluido`+PI 403 `dispute_partial_refund_requires_stripe`. Seller RPC 403 `not_allowed`. Disputa aberta → Edge 403 `order_refund_blocked_status`. Edge status = BD `cancelado` (exacto AY/BE **não** reaberto). |
| BK5 stock | `cancelado` pós-pago 403. Refund pago: qty 1→2, units null, 1×. Race 2× refund: Δqty=1 (500 idempotency + 200 already). |
| BK6 release | `false` com disputa aberta e em `pedido_devolucao`. P1 hostage (acima). |
| BK7 2.º actor | B2 INSERT 403 RLS. B2 spoof `buyer_id` 403. S2 hops 200 []. 2.ª disputa 409 `dispute_already_exists_for_order`. Recusada → reopen 409. Race 2× INSERT n=1. B2 GET replies 200 []. |
| BK8 caixa | Buyer 61,10 € e seller 21,00 € estáveis no pass2/3. Sem Δ anómalo nos probes (pagamentos Stripe TEST, não wallet). |

--------------------------------------------------
## EXACTOS AY/BE (não contam)
--------------------------------------------------

| Exacto | Estado nesta ronda |
|--------|---------------------|
| Seller `pago`→`em_devolucao` | 403 `order_em_devolucao_requires_pedido` |
| Buyer `devolucao_entregue` | 403 `order_buyer_cannot_mark_devolucao_entregue` |
| Edge `status:cancelado` vs BD | iguais (`cancelado`) |

--------------------------------------------------
## DESCARTADOS / FP
--------------------------------------------------

- `BK2.buyer_concluido_mid_return` no pass2: disputa já `recusada`; order nunca saiu de `concluido`. Pass3 HOLD.
- `https://fleaber.app/order_disputes/{buyer}/{oid}`: allowlist TU (`fleaber.app/%`) + needle no path — não é wrap hostil; não conta.
- Anon INSERT disputa: 400 `reason_check` até reason válido; com `danificado` o B2/RLS cobre o 2.º actor.

--------------------------------------------------
## INVARIANTES (poço disputa)
--------------------------------------------------

| ID | Estado |
|----|--------|
| C Release/refund ≤ fundos | HOLD |
| G Refund ≤ captura | HOLD |
| H Parties coerentes | HOLD (B2) |
| E JWT não cria saldo | HOLD (release/partial) |
| — FSM devolução honesto | **FALHA** seller inicia `pedido_devolucao` |

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_bk_20260902T1821/_rtbk.dart`
- `tool/redteam_blind_bk_20260902T1821/pass1.dart` + `pass1.json`
- `tool/redteam_blind_bk_20260902T1821/pass2.dart` + `pass2.json`
- `tool/redteam_blind_bk_20260902T1821/pass3.dart` + `pass3.json`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
