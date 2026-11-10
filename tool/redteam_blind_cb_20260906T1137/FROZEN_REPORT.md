# FROZEN_REPORT — RED TEAM CEGO CB

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 1

```
1. P0? NÃO
2. Quantos P0: 0
3. P1? NÃO
4. Quantos P1: 0
5. P2? SIM
6. Quantos P2: 1
7. P3? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CB_PAYOUT_POS_BRBW_v1
FROZEN_AT: 2026-09-06T10:50:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CB1, CB2, CB3, CB4, CB5, CB6, CB7]
VEREDICTO: FAIL_P2
prefix: RTCB-20260906T1137
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BV/BP **não contados** (HOLD LIVE): cirílico `а`→`a` → **1** Transfer; NBSP mid-key → **1** Transfer; ZWJ/NFC/NFD não retestados como finding.

---

## Missão

Depois do fold BRBW (cirílico + NBSP), ainda 2 Transfers ou refund mentiroso?

**Resposta:** **2 Transfers sim**, com homóglifo **grego** (α/ο/ρ) no lugar da letra latina — o fold só mapeia um subconjunto cirílico e depois **apaga** o resto non-ASCII, por isso a substituição visual **não** colapsa com a chave latina. Refund **não** mentiroso: body `amount`/`refund_amount` ignorados (590 cêntimos da linha); buyer/seller2 403; pós-envio `order_refund_blocked_shipped`. Release cedo (pago / enviado / concluido CTT sem `shipped_at`) → `false`, Δ=0.

Casefold `Payout` vs `payout` → 2 Transfers — **desenho** (sem `toLowerCase`; app `wd_{uuid}_{cents}_{ms}`). Não contar.

---

## Findings abertos

### CB-P2-01 — homóglifo grego na idempotency_key → 2 Transfers

- **Sev:** P2 · **Lente:** CB4 · **Actor:** seller JWT
- **Pré:** `payoutIdempotencyKey` = NFKC + strip ZWJ/BOM + compactar whitespace (NBSP) + fold **só** cirílico lookalike→ASCII + **apagar** `[^\x20-\x7E]`. Sem confusable grego. Sem `toLowerCase`. Flutter: `wd_{userId}_{cents}_{ms}` (ASCII).
- **Repro:**
  1. POST `create-connect-account` `{amount:100, idempotency_key:"rtcbGREEKa1"}`
  2. POST mesma conta `{amount:100, idempotency_key:"rtcbGREEKα1"}` (U+03B1 no lugar do «a»)
- **Esperado:** 1 intenção se a chave visual é a mesma (mapear α→a) **ou** documentar Unicode distinto
- **Obtido:** 2 Transfers `tr_1UCdZDH7FWYUN3jhjqVq8nR2` + `tr_1UCdZGH7FWYUN3jhlzW02WDN`; wallet 76.33 → 74.33 (−2,00 €); `idempotentB=false`
- **Mesma classe (não contar extra):**
  - ο vs o isolado (`rtcbOMICo99x` / `rtcbOMICο99x` U+03BF) → `tr_1UCdcHH7FWYUN3jh2XcuqKcu` + `tr_1UCdcKH7FWYUN3jhkRafOew1` Δ −2 €
  - ρ vs p isolado (`rtcbRHOp99xx` / `rtcbRHOρ99xx` U+03C1) → `tr_1UCdcOH7FWYUN3jhvSZUsazt` + `tr_1UCdcQH7FWYUN3jhnleqrEHF` Δ −2 €
- **Porquê:** apagar α deixa `rtcbGREEK1`; a chave latina é `rtcbGREEKa1` — hashes diferentes. Fold cirílico `а`→`a` **não** cobre grego.
- **Impacto:** levantamento **próprio** duplicado com chave visivelmente quase igual. Sem mint, sem cross-user. Residual Unicode após BRBW (denylist cirílico + strip ≠ confusable).
- **Prova:** `pass1.json` finding `CB-P2-GREEK-ALPHA`; `pass3b.json` ο/ρ isolados `count:false`

Uma classe, vários payloads — **conta 1**.

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Exact cirílico `а`→`a` | CB4 | 1 Transfer (fold BRBW LIVE) |
| Exact NBSP mid-key | CB4 | 1 Transfer (strip whitespace LIVE) |
| Fullwidth `１` vs `1` | CB4 | 1 Transfer (NFKC) |
| WORD JOINER U+2060 no meio | CB4 | 1 Transfer (catch-all non-ASCII) |
| SOFT HYPHEN U+00AD no meio | CB4 | 1 Transfer |
| Hangul filler U+3164 no meio | CB4 | 1 Transfer |
| Casefold `PayoutRtcb1` vs `payoutRtcb1` | CB4 | **2 Transfers** `tr_1UCdZ7H7…` + `tr_1UCdZAH7…` Δ −2 € — **desenho** sem lowercasa; app `wd_uuid_…` |
| PUT / DELETE Connect | CB1 | 405 Method not allowed |
| `amount:[100]` / nested / object / −100 / `0x64` / `１００` | CB4 | 400 Valor inválido |
| `amount:"100"` | CB4 | aceite como 100 cêntimos (desenho JS) — 1 Transfer |
| Race 3× mesma key | CB4 | 1 Transfer `tr_1UCdZkH7FWYUN3jhC8Xv1WJV` |
| crash_inject **sem** secret | CB4 | ignorado; payout 200 normal |
| crash_inject **com** secret + retry mesma key | CB4 | 500 debit órfão → retry 1 Transfer `tr_1UCdYnH7…` (não duplicou) |
| webhook `transfer.created` / `charge.refunded` sem sig | CB4 | 400 `missing_signature` |
| webhook assinatura lixo | CB4 | 400 `invalid_signature` |
| GET stripe-webhook | CB4 | 405 `method_not_allowed` |
| body `destination`/`acct_fake` | CB6 | Transfer **própria** `tr_1UCdYZH7…` (destino cliente ignorado) |
| `user_id` buyer no body | CB6 | 400 Cannot create another user |
| JWT `batata_wallet_payout_debit/finish` | CB6 | 403 GRANT |
| buyer JWT payout | CB6 | 400 Connect sem IBAN |
| web_return trail/http/0.0.0.0/`[::1]`/127.1/metadata/suffix/userinfo/`data:`/`blob:`/`about:` | CB2 | 200 HTML wallet, sem Location hostil |
| buyer `refund-order` | CB3 | 403 Sem permissão |
| seller2 `refund-order` venda seller1 | CB6 | 403 |
| refund body `amount`/`refund_amount`/`total` 999999 | CB3 | refund 590 cêntimos da linha (`already_refunded`/`idempotent`) |
| JWT `batata_finalize_stripe_order_refund` | CB6 | 403 GRANT service_role |
| buyer `pago`→`concluido` CTT Expresso | CB5 | 403 `order_concluido_requires_shipped` |
| PATCH `shipping_method` pós-pago | CB5 | 403 `order_shipping_frozen_after_payment` |
| mão spoof novos: `em mão` / `hand-delivery` / `in person` / `pessoalmente` / `face to face` / `entrega em mãο` / `entrega em mäo` | CB5 | 403 `order_concluido_requires_shipped` |
| release JWT em `pago` | CB3 | `false`, Δ=0 |
| release JWT em `enviado` (não concluido) | CB3 | `false`, Δ=0 |
| release JWT em `concluido` CTT Expresso sem `shipped_at` (estado forçado service) | CB3 | `false`, Δ=0 |
| unship após concluido real | CB5 | 403 `order_shipped_at_immutable`; status continua `concluido` |
| release buyer após enviado→concluido | CB7 | `true`, Δ **+5,00 €** (crédito legítimo); seller/buyer2 `false` |
| 2.º release | CB7 | Δ 0 |
| refund-order após enviado/concluido | CB3 | 403 `order_refund_blocked_shipped` |
| refund então release mão | CB3 | Δ 0 (sem crédito líquido) |
| race 3× refund-order | CB3 | idempotente mesmo `re_`; sem 2 capturas |

**Não é finding:** `service_role` a forçar `status=concluido` (fixture). Actor do exploit = JWT.

**Falsos positivos descartados:** `destination` spoof (Transfer para o Connect do JWT). Par grego ο no pass1 (colisão de hash com α stripped `rtcbGREEK1` — reteste isolado no pass3b confirmou 2 Transfers, mesma classe).

**Contabilidade payout pass1:** wallet seller 84.33 → 68.33 = **−16,00 €** = 16 Transfers de 100 cêntimos (incl. par grego + casefold desenho). Sem mint.

---

## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CB1 Connect/HTTP | SIM | HOLD PUT/DELETE 405 |
| CB2 return hijack | SIM | HOLD origens novas sem 303 hostil |
| CB3 release+refund | SIM | HOLD (buyer 403; release cedo Δ=0; sem crédito pós-refund; refund blocked shipped) |
| CB4 Transfer/webhook | SIM | **P2 grego lookalike**; fullwidth/ZW/NBSP/cirílico/race/crash/webhook HOLD |
| CB5 unship/FSM | SIM | HOLD concluido exige envio; shipped_at imutável; mão spoof novos recusados |
| CB6 actor cruzado | SIM | HOLD user_id/seller2/finalize/debit JWT |
| CB7 Δwallet | SIM | payouts próprios; release +5 € só no ciclo enviado→concluido 1× |

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (debit/finish/finalize 403; 2.º release Δ=0; release cedo Δ=0)
13. Refund excede captura — NÃO (body 999999 → 590 cêntimos)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer indevidamente — PARCIAL: sim em keys lookalike gregas (P2); não na mesma key (race/crash); não em cirílico/NBSP/fullwidth/ZW
16. Stock=1 duas vendas válidas — NÃO COMPROVADO (fora poço)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO (refund-order 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO (fora poço)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia autoridade do cliente no total — NÃO (`destination`/`user_id`/`amount` hostil rejeitados ou ignorados)
27. Conclusão crítica NÃO COMPROVADA — NÃO (Stripe TEST pago + Transfer + refund + release)
28. Saturação / último passe classe nova P0/P1 — NÃO (pass3b só mesma classe P2 grego)

ATROFIA (só exactos cirílico/NBSP/ZWJ/NFC): NÃO  
Poço Stripe TEST pago: SIM (`setup_paid_order` + Transfers Connect TEST)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
