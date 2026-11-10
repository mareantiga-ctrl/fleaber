# FLEABER — Relatório congelado · Red Team independente (cego)

**Projecto:** Fleaber marketplace + live + wallet  
**Ambiente:** Supabase STAGING `fxdknzrqjenzqcvnwqqq` · Stripe **TEST** apenas  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções implementadas:** NÃO  
**FROZEN_AT:** `2026-08-29T14:02:00Z`

**Veredicto:** **A — FAIL_P0**

**Saturação:** **NÃO** (o último passe completo descobriu uma classe P0 nova: mint de wallet via RPC de gorjeta + payout Stripe TEST).

Este documento congela descoberta, severidades e evidência **antes** de qualquer comparação com histórico.

---

## 0. Âmbito e método

Auditoria cega adversarial. Identidades usadas (JWT reais, sem `service_role` nos exploits):

| Papel | UUID |
|---|---|
| Buyer lab | `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` |
| Seller lab | `980f4fa1-0004-42f9-abca-69f1a9c29588` |
| Buyer2 | `e621595b-80f2-49e7-a7c8-01c8d5268c78` |
| Anon | chave `anon` |

`service_role` usado só para fixtures, observação de estado e cleanup do saldo mintado (buyer `93.81 → 39.81` após evidência). O P0 é reproduzível com JWT autenticado.

Três passes: cobertura → variantes/invariantes → composição/races. Stripe TEST completado em: checkout contratual, payout mintado, stock=1 (1.ª captura settle; 2.ª recusada no return path).

---

## 1. Findings

### RT-D-P0-001 — JWT autentica e cria saldo arbitrário via `batata_wallet_apply_tip_once`, depois levanta em Stripe TEST

| Campo | Valor |
|---|---|
| **Severidade** | **P0** |
| **Estado** | OPEN (não corrigido nesta auditoria) |
| **Actor** | Buyer autenticado **ou** seller autenticado (JWT normal) |
| **Superfície** | RPC `SECURITY DEFINER` · `live_tips` pending · Edge `create-live-tip-checkout` · Edge `create-connect-account` |
| **Pré-condições** | Conta autenticada; capacidade de criar uma tip `pending` (checkout de gorjeta, **sem pagar**); `p_wallet_id` = próprio |
| **Impacto** | Criação de fundos Fleaber sem captura Stripe da gorjeta; montante e tipo/descrição controlados pelo cliente; segunda crédito na mesma tip se `p_type` mudar; seller com Connect ready converte saldo mintado numa **Transfer Stripe TEST** |

**Reprodução (buyer):**

1. `POST /functions/v1/create-live-tip-checkout` com JWT buyer, body `{ "seller_id": "<seller>", "amount_eur": 1 }` → cria `live_tips` **pending** (ex. `2fa964d8-…`, `c426d742-…`).
2. `POST /rest/v1/rpc/batata_wallet_apply_tip_once` com JWT buyer:
   ```json
   {
     "p_wallet_id": "bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96",
     "p_tip_id": "<tip pending real>",
     "p_amount": 50,
     "p_type": "venda",
     "p_description": "rt-d mint via tip"
   }
   ```
3. Resposta `true`. Wallet `39.81 → 89.81`. Tx `c1727924-…`.
4. Variante: nova tip + `p_amount=1` → `89.81 → 90.81`.
5. Mesma tip, `p_type`/`p_description` diferentes (`reembolso` / `rt-d other desc`, `p_amount=3`) → **+3 extra** (`90.81 → 93.81`). Idempotência só cobre `(wallet_id, tip_id, type)`.
6. Cross-wallet (buyer credita seller): recusado (`not_allowed` / equivalente). Self-mint é suficiente.
7. Seller: mesmo padrão `8.41 → 18.41` (+10).
8. Seller `POST /functions/v1/create-connect-account` `{ "amount": 1000, "idempotency_key": "rt_d_p0_minted_payout_…" }` → `success`, `transferId=tr_1U9mjiH7FWYUN3jhNElEk8wE`, saldo `18.41 → 8.41`.

**Buyer payout** dos 54 € mintados: falhou (Connect sem IBAN) — saldo ficou mintado até cleanup de laboratório.

**Porquê P0:** compromisso financeiro imediato: JWT normal cria saldo sem fundos da plataforma e um actor com Connect ready **extrai** esse saldo via Transfer TEST. Não é eco HTTP; persistência de `wallets.balance` + `wallet_transactions` + Transfer ID.

**Código (repo, alinhado com o comportamento live):** função `SECURITY DEFINER`, `search_path=public`, **sem** `auth.uid()`, confia em `p_wallet_id` / `p_amount` / `p_type`. Não há `REVOKE`/`GRANT` visível para esta função no SQL de tips — o JWT autenticado tem `EXECUTE` em staging.

Evidência: `probe_p0_tip_mint.json`, `probe_p0_payout.json`.

---

### RT-D-P2-001 — Anon INSERT em `favorites` / `follows` com UUIDs de terceiros

Anon consegue `INSERT` com `user_id` / `follower_id`/`following_id` escolhidos (HTTP 201, rows persistidas). Impacto social (seguir/favoritar em nome de outros), não financeiro. **P2**.

### RT-D-P2-002 — Janela de holds: 8 orders simultâneas com stock=1

Oito `INSERT` de orders no mesmo SKU `quantity=1` foram aceites; `products.quantity` manteve-se 1 até captura. Holds ≠ venda. **P2** (capacidade não exclusiva no hold).

### RT-D-P2-003 — Múltiplas Checkout Sessions no mesmo order / no mesmo stock=1

Seis Sessions no mesmo order; duas Sessions em duas orders do mesmo SKU qty=1. Session ≠ captura. **P2** (janela de pagamento).

### RT-D-P2-004 — Buyer INSERT `premio_rifa`

HTTP 201, mas status **reescrito** para `reserva_pendente`; checkout prize: `Checkout blocked: order is not a raffle prize`. Sem efeito económico comprovado. **P2** (ruído FSM).

### RT-D-P2-005 — Segunda captura stock=1: Stripe diz pagamento recebido, Fleaber recusa settle

Order A: `pago`, `amount_paid_cents=590`, `stock_units_applied=1`, PI `pi_3U9mk1H7FWYUN3jh0tXzj8SN`. Produto `quantity=0`, `is_sold=true`.  
Order B: continua `reserva_pendente`. Return path HTTP 500: «PAGAMENTO RECEBIDO» + «Não foi possível validar o pagamento». Refund **não** aparece na BD. Sem API Stripe neste ambiente → captura líquida permanente da 2.ª Session = **NÃO COMPROVADO**. Duas vendas Fleaber válidas = **NÃO**. **P2** operacional (possível charge preso no TEST).

---

## 2. Ataques que **não** quebraram autoridade (anti-falso-positivo)

| Superfície | Ataque | Resultado live |
|---|---|---|
| CHECKOUT | `amount=50`, qty hostil, `prize_shipping`, `line_total_cents=1` | Servidor cobra contrato (ex. 590 / 905 / 1199) |
| CHECKOUT | Catálogo baixado após hold | Session ainda 590; `contract_unit_cents=500` |
| ORDERS INSERT | `status=pago` + PI + `amount_paid` | Persistido `reserva_pendente`; Stripe IDs stripped |
| ORDERS PATCH | Campos financeiros | HTTP 200, **sem** alteração persistida |
| WALLET RPC | `batata_credit_wallet_once` / debit / payout_finish | `42501` |
| SETTLE privilegiado | `fase2_e2e_settle`, `sec-fase2-e2e-oversell` | 401 sem service_role |
| WEBHOOK | Sem assinatura | 400 `missing_signature` |
| REVIEWS | Sem order paga / identidade alheia / race 6x | `review_order_required` / `review_order_invalid_status` |
| AUTH | `user_type=admin` | Permanece `comprador` |
| AUTH | Seller PATCH perfil buyer | HTTP 200 body `[]` — sem persistência |
| CHAT | SELECT messages | Apenas chats em que o buyer é parte (`e083fd44` = buyer↔seller) |
| LIVE | Stream keys | Sem leak para buyer |
| RAFFLE | INSERT winners | 403 |
| OFFERS | INSERT accepted a 0.50 | 403 |
| MB WAY | Seller `pago` + stock | Consome stock; **não** credita wallet (`amount_paid_cents` null). Off-platform, não mint Fleaber |
| PAYOUT | Mesma idempotency key 4x | 1 Transfer |
| PAYOUT | Keys distintas **concorrentes** | 1 Transfer observado |
| PAYOUT | Keys distintas **sequenciais** | 2 Transfers (intenção J) |
| RPC | `staging_nuke_user_data`, clawback, settle tip from stripe, create prize order | `42501` JWT |
| JWT alg=none | | 401 |

OpenAPI com `service_role` lista funções que o JWT **não** executa — não usar como mapa de grants autenticados.

---

## 3. Matriz (resumo)

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEVERIDADE | EVIDÊNCIA |
|---|---|---|---|---|---|---|
| RPC / WALLET | `apply_tip_once` amount arbitrário em tip pending | buyer JWT | `true`; +50 € | mint | **P0** | `probe_p0_tip_mint.json` |
| RPC / WALLET | mesma tip, type diferente | buyer JWT | +3 € extra | mint dup | **P0** (mesma classe) | idem |
| RPC / WALLET | self-mint + Connect payout 10 € | seller JWT | Transfer `tr_1U9mjiH…` | extracção | **P0** | `probe_p0_payout.json` |
| RPC | `credit_wallet_once` | buyer | 42501 | nenhum | INFO | `probe_cont_raw.json` |
| CHECKOUT | amount cliente 50 | buyer | server 590 | nenhum | INFO | `probe_pass3.json` |
| CHECKOUT | bag line_total=1 | buyer | 1199 | nenhum | INFO | `probe_cont_raw.json` |
| ORDERS | INSERT pago+PI | buyer | status hold | nenhum | INFO | `probe_cont_raw.json` |
| STOCK | 8 holds qty=1 | buyer | 8 holds, qty=1 | janela | P2 | `probe_cont_raw.json` |
| STOCK×STRIPE | 2 Sessions qty=1; pagar A e B | buyer | A pago; B recusado settle | 1 venda | P2 / 13 NÃO COMPROVADO | `stock1_capture_observe.json` |
| RLS | anon favorites/follows | anon | 201 persistido | social | P2 | `probe_cont_raw.json` |
| RAFFLES | INSERT premio_rifa | buyer | 201→reserva_pendente; checkout 400 | ruído | P2 | `probe_cont_raw.json` |
| REVIEWS | insert/forge/race | buyer | 400 | nenhum | INFO | `probe_cont_raw.json` |
| WEBHOOK | unsigned | anon | 400 | nenhum | INFO | `probe_cont_raw.json` |
| PAYOUT | retry mesma key | seller | 1 transfer | nenhum | INFO | `probe_cont_raw.json` |
| LIVEKIT | cleanup buyer | buyer | 401 | nenhum | INFO | `probe_cont_raw.json` |
| SMS hook | anon | anon | 200 body erro headers | sem pump | INFO | `probe_cont_raw.json` (não P1) |

Matriz completa de cobertura no JSON congelado (`matrix[]`).

---

## 4. Invariantes financeiros (tentativa de refutação)

| ID | Invariante | Resultado |
|---|---|---|
| A | Stripe cobra o contrato do servidor | **Mantido** nos checkouts testados (50→590, bag 1c→1199, catálogo pós-hold) |
| B | Buyer não define preço/qty autoritativos | **Mantido** no checkout Edge |
| C | release/refund/payout ≤ fundos legítimos | **REFUTADO** via mint P0 + Transfer seller (fundos não vieram de captura de gorjeta) |
| D | 1 unidade física ≠ 2 vendas válidas | **Não refutado** neste TEST (só A `pago`) |
| E | JWT não cria wallet/ledger/PI/payout authority | **REFUTADO** (wallet + ledger via RPC; payout authority sobre saldo mintado) |
| F | Pagamento off-platform não cria saldo Fleaber | **Mantido** no MB WAY observado (wallet inalterada) |
| G | Refund ≤ captura | Não se obteve refund > captura com JWT; **não refutado** |
| H | Parties coerentes no ciclo checkout | **Mantido** nos orders de laboratório |
| I | 1 intenção payout ≤ 1 Transfer | **Mantido** (mesma key) |
| J | 2 intenções distintas → 2 Transfers | **Mantido** em sequencial |
| K | Catálogo posterior não altera contrato aceite | **Mantido** (590 / contract 500) |
| L | Offer/bundle/discount só com autoridade | Offer INSERT aceite 403; bag ignora line_total cliente |

---

## 5. Máquinas de estado (ordens)

Estados observados: `reserva_pendente`, `aguarda_confirmacao` (MB WAY), `pago`, `cancelado`.  
Buyer não consegue saltar para `pago` com Stripe IDs no INSERT. Seller **consegue** `pago` em fluxo MB WAY e aplicar stock, sem `amount_paid_cents`. Triggers reescrevem `premio_rifa`. Return path não promove B a `pago` quando stock já consumido.

Efeito económico equivalente: **tip pending + RPC** produz crédito de wallet **sem** estado `completed` da tip — caminho paralelo ao settle Stripe da gorjeta.

---

## 6. Races

| Race | n | Estado final |
|---|---|---|
| Holds stock=1 | 8 | qty produto = 1 |
| Checkout Sessions mesmo order | 6 | 6 Sessions criadas |
| Refunds em hold | 4 | todos 422 |
| Payout mesma key | 4 | 1 Transfer |
| Payout keys distintas concorrentes | 4 | 1 Transfer |
| Reviews | 6 | todos 400 |
| Stock=1 duas Sessions + pagar A depois B | 2 | 1 `pago`; 2.ª settle recusado |

---

## 7. Stripe TEST

| Caso | Distinção |
|---|---|
| Checkout amount hostil | SESSION CRIADA a 590 (contrato) — não pago nesta sonda |
| Stock=1 order A | **CAPTURA REAL TEST** + settle Fleaber `pago` 590 |
| Stock=1 order B | SESSION + return «pagamento recebido»; **sem** settle; captura líquida **NÃO COMPROVADA** |
| Payout mintado seller 10 € | Transfer TEST `tr_1U9mjiH7FWYUN3jhNElEk8wE` — **CAPTURA/MOVIMENTO REAL TEST** a partir de saldo ilegítimo |

---

## 8. Superfícies obrigatórias — cobertura

AUTH/PROFILES, ORDERS/FSM, PRODUCTS/CATALOG/PRICE/QTY, CHECKOUT, STRIPE SESSION, SETTLE/RETURN, BAG, WALLET/LEDGER/PAYOUT, STOCK, REFUNDS (JWT recusado / hold 422), DISPUTES (RPC 400/403), LIVE/LIVE ITEMS (mark sold not_found), RAFFLES, TIPS (**P0**), CHAT, REVIEWS, STORAGE (não se obteve object leakage com JWT), MUX/LIVEKIT (401 cleanup), RPCs/SECURITY DEFINER/GRANTs/RLS/TRIGGERS/EDGE.

PS/OCR: não exercido como interface de pagamento (fora do caminho financeiro principal nesta ronda).

---

## 9. Lacunas

- Sem `STRIPE_SECRET` no env de ops: 2.ª Session stock=1 — estado Stripe (captured vs refunded) **não** lido na API Stripe.
- Partial refund + full refund + release+refund **na mesma order paga Stripe** não foi composto até ao fim (P0 já saturava o veredicto; refund>captura não demonstrado).
- Conluio buyer+seller além de MB WAY off-platform: não se provou mint conjunto para além do P0 individual.
- Storage signed URLs alheias: não se provou leak.
- Após descoberta P0 **não** se correu um passe extra completo sem nova classe P0/P1 → saturação = NÃO.

---

## 10. Cleanup laboratório

Buyer wallet restaurado `93.81 → 39.81` via `service_role` (`cleanup_wallet_observe.json`). Seller ficou `8.41` após o Transfer dos 10 € mintados. RPC **não** foi alterado.

---

## 11. Checklist final

1. P0 aberto encontrado: **SIM**  
2. Quantos P0: **1** (classe única: mint via `apply_tip_once`)  
3. P1 aberto encontrado: **NÃO** (candidatos iniciais despromovidos por anti-FP)  
4. Quantos P1: **0**  
5. Buyer manipula preço autoritativo: **NÃO**  
6. Buyer manipula qty autoritativa: **NÃO**  
7. Seller falsifica pagamento **plataforma** (Stripe/wallet captura): **NÃO** (MB WAY marca `pago`/stock sem creditar wallet)  
8. JWT cria saldo/fundos: **SIM**  
9. Refund excede captura: **NÃO** (não demonstrado)  
10. Release+refund cria dinheiro líquido: **NÃO** (não demonstrado; mint P0 é outro caminho)  
11. Payout duplica Transfer da **mesma** intenção: **NÃO**  
12. Stock=1 duas vendas válidas: **NÃO**  
13. Stock=1 duas capturas líquidas permanentes: **NÃO COMPROVADO**  
14. Bypass capacidade/reserva: **SIM** no hold (P2); **NÃO** na venda settle A vs B  
15. Cross-user financeiro: **NÃO** (self-mint; cross-wallet recusado)  
16. Cross-user dados sensíveis: **NÃO**  
17. Buyer assume seller/admin: **NÃO**  
18. Seller assume buyer/admin: **NÃO**  
19. Reviews forjadas/duplicadas: **NÃO**  
20. RPC/SECURITY DEFINER perigoso: **SIM** (`batata_wallet_apply_tip_once`)  
21. RLS crítico (financeiro) quebrado: **NÃO** (social P2)  
22. Edge confia autoridade cliente para preço/qty: **NÃO**; tip checkout cria pending usável no P0  
23. Conclusão crítica NÃO COMPROVADA: **SIM** (item 13)  
24. Regressão funcional relevante: **NÃO** (auditoria; sem deploy)  
25. Último passe encontrou nova classe P0/P1: **SIM** (P0 tips)  
26. Saturação atingida: **NÃO**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**

---

## 12. Veredicto

**A — FAIL_P0**

Um P0 confirmado com prova forte (antes/depois wallet, txs, Transfer TEST). Zero P1 após anti-falso-positivo. Invariantes A/B de checkout mantidos. Saturação não atingida.

Probes: `tool/redteam_indep_d_20260829/`.
