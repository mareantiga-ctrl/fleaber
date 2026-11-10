# FROZEN_REPORT — RED TEAM CEGO DK

## CONTAGEM

```
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0
```

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DK_RLS_STORAGE_FSM_POS_DBDG_v1
FROZEN_AT: 2026-09-06T16:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DK1, DK2, DK3, DK4, DK5, DK6, DK7]
probes_na_tabela: 33 (≥14)
VEREDICTO: PASS_CEGO_SATURADO
```

Prefixo: `RTDK-20260906T1610`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`), oráculos BD, chats.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `aa782327-f9bd-4a8a-87d4-09f710b724c1` · S2 `4a111eed-aabe-47c8-a4bc-7da2f2f82acb`

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (`order_money_fields_immutable`)
10. Buyer manipula qty autoritativa — NÃO (qty 1→1)
11. Seller falsifica pagamento plataforma — NÃO (pago exige captura; off-platform exige prova)
12. JWT cria saldo/fundos — NÃO (release com disputa = `false`, Δseller 0)
13. Refund excede captura — NÃO (590¢ idempotente `re_3UChpiH7…`)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (GET storage B2 `NoSuchKey`; LIST `[]`; sign null; SELECT order `[]`)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (S2 PATCH `200 []`, status permanece `pago`)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (release com disputa = false)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO
27. Regressão funcional (happy path partido) — NÃO (Stripe pago; MB WAY pago com prova 200; cancel restaura hold; refund 0→1)
28. Saturação atingida — SIM (P0–P2=0, quota 33≥14, 7/7 lentes)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Buyer **não** marca `pago` / não lê storage alheio / não PATCH money fields.  
FSM: transições ilegais deny; stock coerente em cancel/refund.

**Resposta:** IDOR REST em encomenda/chat/perfil/follows **negado** (403 ou `200 []` sem persistir). Storage `order_proofs/{outro}/` e traversal `../` **403 RLS**. Money cols (`amount_paid_cents`, `stripe_*`, `quantity`, `contract_*`, `payment_method` após Session) **42501 immutable**. Seller MB WAY sem prova **403**; com prova signed **200 pago**. `reserva_pendente` → `enviado`/`concluido` **403 requires_capture**. Cancel JWT pré-pago restaura hold 0→1 (plataforma e MB WAY). Cancel pós-pago **403**. Refund em `enviado` **403 blocked_shipped**. Refund em `pago` qty **0→1→1** idempotente 590¢. Disputa 201; 2.ª **409**; release **false** Δseller 0.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados** como finding:
- Buyer PATCH própria order `status=pago` → 403 `order_status_requires_capture` (clássico)
- Upload `order_proofs/{B1}/…` como B2 → 403 RLS (proof path alheio clássico)
- PaysafeCash — não usado

Novos (contam para quota, todos FAIL/defesa): PATCH/SELECT IDOR B2, LIST/sign storage, traversal `../`, chat insert/PATCH, follows spoof, profile PATCH, money/stripe/qty/contract, payment_method após `cs_test_`, seller pago sem/com prova, FSM skip, cancel hold, refund ×2, disputa/release.

Residual clássico ≪ 50% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| DK1 IDOR | B2 PATCH/GET order alheia `200 []`. INSERT spoof `order_buyer_attribution_denied`. Chat 403 RLS. Follows 403. Profile `200 []` nome inalterado. S2 PATCH `200 []`. |
| DK2 storage | GET B2 `NoSuchKey`. LIST prefix B1 `[]`. Sign null. Upload alheio 403. Traversal `../` 403. Upload próprio 200. |
| DK3 money immutable | `amount_paid_cents` / `stripe_*` / qty / contract / `payment_method` pós-Session / `wallet_release_processed_at` → 42501. 590¢ intacto. |
| DK4 FSM | `reserva`→`enviado`/`concluido` 403 capture. Cancel pós-pago 403. Refund em `enviado` 403 `order_refund_blocked_shipped`. Happy `pago`→`enviado`→`concluido` 200. |
| DK5 stock | Cancel plataforma avail 0→1. Cancel MB WAY 0→1. Refund `pago` qty 0→1→1 (não ×2). |
| DK6 disputa | 1.ª POST 201 `aeb6a0bd-…`. 2.ª 409 `dispute_already_exists_for_order`. Release `false`. |
| DK7 actor | Buyer não marca pago. Seller pago off sem prova deny / com prova OK. S2 não toca order S1. Release Δ 0. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia principal: **5,90 €** (`amount_paid_cents=590`) order `665d8cdb-…`. PI `pi_3UChoLH7FWYUN3jh1QkHcQj7`.
- Refund C3: order `00da6765-…` PI `pi_3UChpiH7FWYUN3jh13k9uciI` → `re_3UChpiH7FWYUN3jh1tJd6Ua6` **590¢** idempotente; status `pago`→`cancelado`; qty **0→1→1**; Δbuyer 0 · Δseller 0.
- Refund em `enviado` (`049920de-…`): Edge 403 `order_refund_blocked_shipped`; qty permanece 0.
- Stock hold: cancel plataforma `fae5bce4-…` avail **0→1**; cancel MB WAY `c14d4b27-…` avail **0→1**.
- Release com disputa `677d2913-…` / disputa `aeb6a0bd-…`: Δ seller **0**.
- MB WAY com prova: order `71b3cead-…` status **pago**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

Nenhum finding aberto (P0–P3 = 0).

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥14 linhas · ≥1 encomenda Stripe TEST paga · A≥5 B≥4 C≥5.  
`FAIL` = ataque falhou (defesa segurou / happy path OK). `HOLD` = finding. Controlos clássicos na tabela como FAIL, **não contar** HOLD.

| # | probe_id | actor | recurso | HTTP/RPC | BD | HOLD\|FAIL\|SKIP |
|---|----------|-------|---------|----------|----|------------------|
| 1 | DK-A1.patch_status_alheia | B2 | orders.status order B1 | 200 `[]` | status=`pago` inalterado | FAIL |
| 2 | DK-A1b.patch_money_shipping_alheia | B2 | shipping + amount_paid | 200 `[]` | 590 / shipping intactos | FAIL |
| 3 | DK-A1c.select_order_alheia | B2 | GET orders B1 | 200 `[]` | 0 rows | FAIL |
| 4 | DK-A1d.insert_spoof_buyer | B2 | POST orders buyer_id=B1 | 403 `order_buyer_attribution_denied` | sem row | FAIL |
| 5 | DK-A1e.s2_patch_order | S2 | PATCH status enviado | 200 `[]` | status=`pago` | FAIL |
| 6 | DK-A2.get_storage_alheio | B2 | GET order_proofs/{B1}/… | 400 `NoSuchKey` | objecto B1 existe | FAIL |
| 7 | DK-A2b.list_prefix_alheio | B2 | LIST prefix B1 | 200 `[]` | 0 names | FAIL |
| 8 | DK-A2c.sign_object_alheio | B2 | object/sign B1 | 403 null | sem token | FAIL |
| 9 | DK-A3.upload_proofs_outro | B2 | POST order_proofs/{B1}/ | 400 403 RLS | (clássico, não contar HOLD) | FAIL |
| 10 | DK-A3b.upload_dotdot_proofs | B2 | `order_proofs/{B2}/../{B1}/` | 400 403 RLS | sem cross GET | FAIL |
| 11 | DK-A4.msg_noutro_chat | B2 | POST chat_messages chat B1-S1 | 403 RLS chat_messages | sem inject | FAIL |
| 12 | DK-A4b.patch_msg_alheia | B2 | PATCH msg B1 | 200 `[]` | text original | FAIL |
| 13 | DK-A5.follow_spoof_follower | B2 | POST follows follower_id=B1 | 403 RLS follows | INSERT negado | FAIL |
| 14 | DK-A5b.patch_profile_alheio | B2 | PATCH profiles B1 | 200 `[]` | full_name Maestro Buyer | FAIL |
| 15 | DK-CTRL.buyer_patch_pago | B1 | PATCH status=pago própria | 403 `order_status_requires_capture` | reserva_pendente (clássico) | FAIL |
| 16 | DK-B1.patch_amount_paid | B1 | amount_paid_cents=1 | 403 `order_money_fields_immutable` | 590→590 | FAIL |
| 17 | DK-B1b.patch_stripe_ids | B1 | stripe_pi + cs | 403 immutable | pi `pi_3UChoLH7…` intacto | FAIL |
| 18 | DK-B1c.seller_patch_amount | S1 | amount_paid_cents=99999 | 403 immutable | 590→590 | FAIL |
| 19 | DK-B1d.patch_wallet_release_flag | B1 | wallet_release_processed_at | 403 `order_wallet_release_flag_immutable` | flag=null | FAIL |
| 20 | DK-B2.patch_pm_after_session | B1 | payment_method após cs_test | 403 immutable | pm `Pagamento na app`; sid `cs_test_a1LWG3…` | FAIL |
| 21 | DK-B3.seller_pago_sem_prova | S1 | MB WAY status=pago | 403 `order_mbway_pago_requires_proof` | reserva_pendente | FAIL |
| 22 | DK-B3b.seller_pago_com_prova | S1 | pago + proof signed | **200** | status=`pago` `71b3cead-…` | FAIL |
| 23 | DK-B4.patch_qty | B1 | quantity=99 | 403 immutable | 1→1 | FAIL |
| 24 | DK-B4b.patch_contract | B1 | contract_unit_cents/qty | 403 immutable | unit 590 cq 1 | FAIL |
| 25 | DK-C1.reserva_to_enviado | S1 | reserva → enviado | 403 `order_status_requires_capture` | reserva_pendente | FAIL |
| 26 | DK-C1b.reserva_to_concluido | B1 | reserva → concluido | 403 requires_capture | reserva_pendente | FAIL |
| 27 | DK-C2.cancel_plat_stock | S1 | cancel reserva plataforma | 200 cancelado | avail **0→1** | FAIL |
| 28 | DK-C2b.cancel_off_stock | S1 | cancel reserva MB WAY | 200 cancelado | avail **0→1** | FAIL |
| 29 | DK-C2c.cancel_pago_denied | S1 | pago → cancelado | 403 `order_cancel_denied_post_pay` | pago | FAIL |
| 30 | DK-C3a.refund_blocked_enviado | S1 | refund-order em enviado | 403 `order_refund_blocked_shipped` | qty 0→0 | FAIL |
| 31 | DK-C3.refund_stock_x2 | S1 | refund-order ×2 em pago | 200 590¢ idempotente `re_3UChpiH7…` | qty **0→1→1** Δ 0 | FAIL |
| 32 | DK-C4.release_com_disputa | B1 | RPC release + disputa | 200 `false` | disputa 201 Δseller=0 | FAIL |
| 33 | DK-C5.segunda_disputa | B1 | 2.ª POST order_disputes | 409 `dispute_already_exists_for_order` | first=`aeb6a0bd-…` | FAIL |

DK-A (IDOR/storage): linhas 1–15 = **15** (≥5).  
DK-B (money): 16–24 = **9** (≥4).  
DK-C (FSM/stock): 25–33 = **9** (≥5).  
**Total 33 ≥ 14.** Stripe TEST pago: linhas 1, 16, 31, 32. Happy MB WAY com prova: linha 22 FAIL (200). Controlos clássicos linhas 9 e 15 FAIL (não contar HOLD).

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- RLS orders: PATCH/GET alheia → `200 []` (sem persistir); spoof buyer → 403
- Storage: B2 não lê, não lista, não assina, não escreve no prefixo B1; `../` 403
- Chat/follows/profiles: INSERT/PATCH alheio deny
- Money/stripe/qty/contract/payment_method/wallet flag → 42501
- Seller off-platform: sem prova deny; com prova signed → pago
- FSM skip pago deny; cancel pré-pago restaura hold; cancel pós-pago deny
- Refund enviado deny; refund pago +1 uma vez, 2.ª call idempotente mesmo `refund_id`
- 2.ª disputa 409; release XOR disputa
- GET storage alheio devolve `NoSuchKey` (não 403) — objecto escondido, sem loot

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_dk_20260906T1610/` — `_rtdk.dart`, `pass1.dart`, `pass1.json`, `confirm_c3.dart`, `confirm_c3.json`, este relatório.

**NÃO CORRIGIR.**
