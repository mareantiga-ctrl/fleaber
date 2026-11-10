# Fleaber — Auditoria cega independente (Red Team)

**FROZEN_AT:** `2026-08-30T12:05:00Z`  
**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções implementadas:** NÃO  

Identidades (JWT reais, nunca service_role como atacante):

- anon (chave `anon`)
- buyer laboratório `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96`
- seller laboratório `980f4fa1-0004-42f9-abca-69f1a9c29588`
- buyer2 descartável `7c0e2202-2f11-4c0f-a87f-122527593a29` (criado só para isolamento)

`service_role` só para fixtures, observação e cleanup.  
Harness `sec-fase2-e2e-oversell` + segredo de staging usado **apenas** para completar captura Stripe TEST (fixture), nunca como prova de exploit JWT.

Probes: `tool/redteam_cega_20260830T1243/`  
Bruto: `out/pass1.json`, `out/pass2.json`, `out/pass3.json`, `out/pass3b_verify.json`, `out/pass4.json`, `frozen.json`

---

## Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0 comprovados. Zero P1 comprovados. Invariantes financeiros atacados em live. Composição e races executadas. Último passe completo sem nova classe P0/P1. Saturação = SIM, com limitações explícitas abaixo.

---

## Findings

Nenhum P0/P1. Residuais P2/P3:

| ID | Sev | Título | Actor | Estado |
|----|-----|--------|-------|--------|
| CEGA-P3-01 | P3 | `batata_live_item_stock` executável por anon | anon | OPEN |
| CEGA-P3-02 | P3 | Seller JWT enumera email→UUID (rate 5/h) | seller | OPEN |
| CEGA-P3-03 | P3 | JWT tem EXECUTE em RPCs de release/refund (fail-closed interno) | buyer/seller | OPEN |
| CEGA-P3-04 | P3 | Race de refund duplicado: flags HTTP inconsistentes, mesmo `refund_id` Stripe | seller | OPEN |
| CEGA-P3-05 | P3 | Review off-platform inserível; `purchase_verified=false`; fora da reputação pública | buyer | OPEN |
| CEGA-P2-01 | P2 | Resume de payout por mesmo `amount_cents` pode colapsar duas intenções concorrentes da mesma conta | seller | OPEN |

### CEGA-P3-01

**Pré-condição:** nenhum JWT.  
**Reprodução:** `POST /rest/v1/rpc/batata_live_item_stock` com `p_live_item_id` válido.  
**Resultado:** HTTP 200 com `total_qty`, `price`, `product_id`, `live_id`.  
**Impacto:** inteligência de inventário, sem mutação.  
**Evidência:** `out/pass2.json` LIVE_ITEM stock as anon.

### CEGA-P3-02

**Pré-condição:** JWT vendedor.  
**Reprodução:** `rpc batata_find_user_id_by_email`. Buyer recebe `null`. Seller recebe UUID do email alvo.  
**Impacto:** enumeração lenta (5/h).  
**Evidência:** `out/pass1.json` AUTH email→uuid.

### CEGA-P3-03

JWT chama `batata_release_seller_wallet_for_order` / `batata_refund_buyer_wallet_for_order` (HTTP 200).  
Efeito económico: `false` fora de `concluido`/`devolvida`; off-platform `true` **sem** crédito (repro isolado: saldo inalterado, zero `wallet_transactions`).  
**Evidência:** `out/pass3b_verify.json` `repro_release` + `repro_tx=[]`.

### CEGA-P3-04

Dois `refund-order` concorrentes no mesmo PI: um `already_refunded=true`, outro `false`; ambos `refund_id=re_3UA7MmH7FWYUN3jh0fFy8L3w`. Uma captura Stripe, um refund.  
**Evidência:** `out/pass3.json` RACE dual seller refund.

### CEGA-P3-05

Após ciclo MB WAY `reserva_pendente → reservado → pago → enviado → concluido` (seller atesta pagamento off-platform), buyer insere review.  
`purchase_verified=false`. `reviews_public_ratings` não a devolve. Duplicado → `review_duplicate`.  
**Evidência:** `out/pass3b_verify.json` `review_mbway` / `public_ratings_mbway`.

### CEGA-P2-01

Três pedidos de levantamento a 100 cêntimos (duas keys iguais + uma diferente) devolveram o mesmo `transferId` `tr_1UA7Mt…` enquanto outra sessão da **mesma** conta seller (lab partilhado) tinha débito aberto desse montante.  
Com montante único 123 cêntimos, duas keys distintas → duas Transfers (`tr_1UA7OW`, `tr_1UA7OY`) e débito 4.00→2.77→1.54.  
**Impacto:** não cria Transfer extra; pode fundir retries/concorrência do mesmo seller.  
**Evidência:** `out/pass3.json` PAYOUT; `out/pass3b_verify.json` `payout_uniq`.

---

## Superfícies testadas

| Superfície | Ataques | Resultado principal |
|------------|---------|---------------------|
| AUTH / PROFILES | `user_type=admin`; PII seller; email UUID | user_type permanece comprador; IBAN não via SELECT profiles; enum só seller |
| ORDERS / FSM | INSERT pago/qty 99/stripe fake; PATCH pago/enviado/entregue/concluido/premio_rifa | hold `order_hold_exceeds_stock`; PATCH 200 mas estado final `pendente`/`reserva_pendente` |
| PRICE / CONTRACT | `price_total=0.01`; catalog 20→0.50 após selo | contrato 2000 cêntimos; checkout 2165 cêntimos (itens+protecção); 2ª order nova usa 0.50 |
| QUANTITY | qty 99; 2ª order stock=1; race 20 inserts | bloqueado no hold; race `ok=0` extra |
| CHECKOUT / SESSION | amount=50; qty=99; swap product/seller; cross-buyer; 10× mesmo order | servidor ignora amount; 2165 cêntimos; reused_session; alheio 400 |
| SETTLE / RETURN | GET anon em Session **não paga** | texto «ainda não confirmado»; order sem `amount_paid` |
| STRIPE TEST captura | fixture e2e `setup_paid_order` (não é exploit JWT) | PI 590 cêntimos, status `pago`, stock aplicado |
| REFUND | buyer; stranger; dual seller; refund após release | 403 buyer/stranger; 1 refund Stripe; clawback seller 24→19 |
| WALLET / LEDGER | INSERT saldo; UPDATE balance; TX mint; credit/debit RPC | 403 INSERT; UPDATE 0 rows; RPC 403 |
| PAYOUT | amount 999999 buyer; 1 cêntimo seller; retry key; duas keys 123 cêntimos | buyer sem Connect; seller débito correcto; J cumpre com montantes distintos |
| STOCK | stock=1 dual INSERT; live accept qty 99 | hold; `qty_exceeds_stock` |
| BAG / RESERVAS | qty 99; stranger update; PATCH converted | cap stock; `not_allowed`; 0 rows |
| OFFERS | INSERT self-accepted / pending 0.01 | RLS 403 |
| TIPS | INSERT paid; checkout 0.01 / 9999 / seller=self | RLS 403; Invalid / too high |
| RAFFLES | SELECT `draw_seed`; tick buyer | 403 coluna; `not_allowed` |
| MUX / LIVEKIT | SELECT stream keys; create-mux buyer vs seller; complete alheio | 403 colunas; buyer lab 403; seller cria (papel vendedor); complete alheio 403 |
| BANKING | RPC IBAN stranger vs relação MB WAY | buyer2 `[]`; buyer com order reservado vê IBAN (contexto legítimo) |
| CHAT | SELECT buyer / stranger | próprio ou vazio; stranger `[]` |
| REVIEWS | sem order; impersonate; dup; off-platform | colunas/RLS/trigger; dup 409; verified false |
| DISPUTES | SELECT cross; INSERT | só parties; schema INSERT falhou (não é bypass) |
| STORAGE | list buckets/provas/chat_media | provas só path próprio; catálogo público `chat_media` |
| DEVICE TOKENS | SELECT | só `seller_id=self` (buyer lab tem tokens próprios, hash não plaintext) |
| PS / OCR | ingest sem token; pairing 000000 | 401 / invalid_or_expired |
| EDGE admin | fase2_e2e_settle JWT; e2e oversell JWT; webhook unsigned; nuke; SMS hook | 401/400/403 |
| RPC DEFINER | credit/debit/payout_debit/clawback/lab_clear/prize | 401/403 JWT |
| OpenAPI | dump anon | 401 só service_role |

---

## Invariantes

| | Invariante | Resultado live |
|---|------------|----------------|
| A | Stripe cobra o contrato servidor | Session `server_amount_cents`/`amount_total`=2165 com catálogo 20€ + protecção; body `amount=50` ignorado |
| B | Buyer não define preço/qty autoritativos | Contrato selado 2000/1; qty 99 rejeitada; PATCH money não baixa `contract_unit_cents` |
| C | Release/refund/payout ≤ fundos reais | Off-platform release não credita; Stripe release +5 depois clawback −5; refund PI = 590 |
| D | Uma unidade ≠ duas vendas válidas | stock=1: 2ª INSERT `order_hold_exceeds_stock`; race 20× = 0 extras |
| E | JWT não cria saldo/PI/session authority | wallet INSERT 403; credit RPC 403; stripe IDs no INSERT rejeitados |
| F | Pagamento off-platform ≠ saldo Fleaber | Repro MB WAY: release `true`, saldo igual, `tx=[]` |
| G | Refund ≤ captura | Dual refund → um `re_…`; amount_cents 590 |
| H | Parties coerentes | Checkout alheio «does not belong to buyer»; PATCH seller_id congelado |
| I | Uma intenção de payout ≤ uma Transfer (mesma key) | Retry mesma key → mesmo `transferId` |
| J | Duas intenções distintas → duas Transfers | 123 cêntimos, duas keys → `tr_1UA7OW` e `tr_1UA7OY` |
| K | Catálogo posterior ≠ contrato aceite | 1ª order 20€/2165 cêntimos após drop para 0.50€ |
| L | Offer/bag só com autoridade | Offer INSERT 403; bag qty 99 `qty_exceeds_stock` |

---

## Races

| Race | n | Estado final |
|------|---|--------------|
| 20 INSERT order stock=1 (buyer+buyer2) | 20 | 1 order `pendente`; 0 extras |
| 10 checkout mesmo order | 10 | 10× HTTP 200; mesma Session (reuse) |
| 2 checkout duas orders qty=2 | 2 | duas Sessions (capacidade 2, não oversell) |
| 2 refund seller mesmo PI | 2 | 1 Stripe refund |
| 2 release buyer order capturada `concluido` | 2 | 1 crédito (`true`+`false`) |
| 2 payout mesma key 100 cêntimos | 2 | 1 Transfer (idempotência) |
| 2 payout keys distintas 123 cêntimos | 2 | 2 Transfers + 2 débitos |
| 2 reviews mesma order | 2 | 1 insert + `review_duplicate` |

---

## Stripe TEST

| Classe | O quê | Resultado |
|--------|-------|-----------|
| SESSION CRIADA | `create-payment-intent` JWT, contrato 20€ mão | `cs_test_a1r2Tzyk…`, 2165 cêntimos |
| SESSION NÃO PAGA + GET settle | anon/buyer | sem captura; order continua `reserva_pendente` |
| CAPTURA REAL TEST | fixture e2e PI `pm_card_visa` 590 cêntimos | `pago`, `amount_paid_cents=590`, stock=1 |
| CAPTURA LÍQUIDA | refund seller | PI reembolsado; order `cancelado` |
| RELEASE+REFUND | captura 590 → release seller +5.00 → refund Stripe | seller 24→19; buyer carteira 10.00 inalterada (volta ao cartão TEST) |

Não se classificam duas Sessions como duas vendas. Duas Sessions no mesmo order foram a **mesma** Session reutilizada.

---

## Composição executada

- order × catalog drop × checkout  
- order × Stripe TEST × dual refund  
- order × release × refund (clawback)  
- stock=1 × dual INSERT × dual JWT  
- bag qty × stock live  
- review × order off-platform × reputação pública  
- payout × retry key × key distinta  
- settle GET × session não paga  
- banking RPC × stranger vs relação MB WAY  
- mux create × papel comprador vs vendedor  

---

## Lacunas / limitações

1. Contas de laboratório **partilhadas** com outros testes no mesmo projecto (ex. chaves `RTB3-20260830T1250*` no ledger de payout). Saldos globais não são prova; usou-se repro isolado + `wallet_transactions` por `order_id`.
2. Sem `STRIPE_SECRET_KEY` local: Sessions Checkout da app **não** foram pagas com cartão 4242. Captura completa = PI TEST via harness de staging (fixture).
3. Não se completou o ciclo «duas Checkout Sessions distintas → duas capturas líquidas permanentes» no mesmo stock=1 (a 2ª order nem chega a nascer; a 2ª Session no mesmo order é reuse).
4. OpenAPI PostgREST não é dumpável com anon (401 service_role) — inventário RPC por lista candidata + erros PGRST.
5. `product_offers` INSERT JWT bloqueado; o caminho UI de ofertas não foi reconstruído na totalidade (não há bypass encontrado).
6. Um directo Mux foi criado no pass1 (seller lab) e outro no pass2 (buyer2 com `user_type` vendedor de fixture). Encerrados / `status=ended` via complete ou service. Custo Mux TEST, não exploit de comprador lab original (403).

---

## Saturação

- Superfícies críticas atacadas: SIM  
- Invariantes A–L testados: SIM  
- Composição: SIM  
- Races: SIM  
- Último passe completo (pass 4: settle unpaid, offers, bag converted) sem nova classe P0/P1: SIM  
- **SATURAÇÃO = SIM**

---

## Checklist final

1. P0 aberto encontrado: **NÃO**  
2. Quantos P0? **0**  
3. P1 aberto encontrado: **NÃO**  
4. Quantos P1? **0**  
5. Buyer consegue manipular preço autoritativo: **NÃO**  
6. Buyer consegue manipular qty autoritativa: **NÃO**  
7. Seller consegue falsificar pagamento plataforma: **NÃO** (off-platform `pago` não cria captura Stripe nem saldo)  
8. JWT consegue criar saldo/fundos: **NÃO**  
9. Refund pode exceder captura: **NÃO**  
10. Release+refund cria dinheiro líquido: **NÃO**  
11. Payout pode duplicar Transfer indevidamente: **NÃO** (mesma key = 1 Transfer; keys+montantes distintos = 2)  
12. Stock=1 pode produzir duas vendas válidas: **NÃO**  
13. Stock=1 pode produzir duas capturas líquidas permanentes: **NÃO** (e Sessions duplas no mesmo order = reuse, não duas capturas)  
14. Existe bypass de capacidade/reserva: **NÃO** (pending qty>stock não converte)  
15. Existe cross-user financeiro: **NÃO**  
16. Existe cross-user de dados sensíveis: **NÃO** (IBAN só com relação off-platform pós-aceitação; provas storage só path próprio)  
17. Buyer pode assumir autoridade seller/admin: **NÃO** (`user_type` imutável no UPDATE)  
18. Seller pode assumir autoridade buyer/admin: **NÃO**  
19. Reviews podem ser forjadas/duplicadas: **NÃO** (dup bloqueado; off-platform não entra na média pública)  
20. RPC/SECURITY DEFINER perigoso encontrado: **NÃO** (EXECUTE JWT em release/refund sem efeito económico indevido)  
21. RLS crítico quebrado: **NÃO**  
22. Edge Function confia em autoridade do cliente: **NÃO** (amount/qty/product do body não mandam)  
23. Alguma conclusão crítica ficou NÃO COMPROVADA: **SIM** (duas Sessions Checkout pagas até captura líquida permanente no mesmo SKU=1 — ver lacuna 3)  
24. Houve regressão funcional relevante: **NÃO** (auditoria sem patches)  
25. Último passe encontrou nova classe P0/P1: **NÃO**  
26. Saturação atingida: **SIM**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**
