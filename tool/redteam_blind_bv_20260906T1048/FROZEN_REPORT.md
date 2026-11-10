# FROZEN_REPORT — RED TEAM CEGO BV

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 2

```
1. P0? NÃO
2. Quantos P0: 0
3. P1? NÃO
4. Quantos P1: 0
5. P2? SIM
6. Quantos P2: 2
7. P3? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_BV_PAYOUT_POS_BLBQ_v1
FROZEN_AT: 2026-09-06T10:00:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BV1, BV2, BV3, BV4, BV5, BV6, BV7]
VEREDICTO: FAIL_P2
prefix: RTBV-20260906T1048
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BP/BJ **não contados** (HOLD LIVE): ZWJ não retestado como finding; NFC/NFD `café` não retestado; GET `web_return_origin=https://2130706433` → **200 HTML wallet** (sem 303 loopback); PUT Transfer → **405**; `amount:true` → **400** inválido.

---

## Missão

Depois do fecho NFKC/ZWJ, ainda tiro saldo 2× ou fico `concluido` sem envio?

**Resposta:** **saldo 2× sim**, com chaves *lookalike* que o NFKC **não** colapsa: homóglifo cirílico e NBSP no meio vs sem espaço → **2 Transfers + Δwallet −2 €** cada par. `concluido` sem envio **não**: buyer CTT/`hand delivery`/etc. → `order_concluido_requires_shipped`; release CTT sem `shipped_at` → `false`, Δ=0.

Casefold `Payout` vs `payout` também deu 2 Transfers — **desenho** (Edge sem `toLowerCase`; app gera `wd_{uuid}_{cents}_{ms}`). Não contar.

---

## Findings abertos

### BV-P2-01 — homóglifo cirílico na idempotency_key → 2 Transfers

- **Sev:** P2 · **Lente:** BV4 · **Actor:** seller JWT
- **Pré:** `payoutIdempotencyKey` = NFKC + strip ZWJ/BOM + trim; **sem** confusable fold; **sem** `toLowerCase`. Flutter: `wd_{userId}_{cents}_{ms}` (ASCII).
- **Repro:**
  1. POST `create-connect-account` `{amount:100, idempotency_key:"rtbvlatinx"}`
  2. POST mesma conta `{amount:100, idempotency_key:"rtbvаtinxx"}` (U+0430 no lugar do «a»)
- **Esperado:** 1 intenção se a chave visual é a mesma (ou documentar Unicode distinto)
- **Obtido:** 2 Transfers `tr_1UCcnGH7FWYUN3jhGZflgUfV` + `tr_1UCcnJH7FWYUN3jhFhLFQuav`; wallet 86.33 → 84.33 (−2,00 €); `idempotentB=false`
- **Impacto:** levantamento **próprio** duplicado com chave visivelmente quase igual. Sem mint, sem cross-user. Residual da classe Unicode após ZWJ/NFKC.
- **Prova:** `pass1.json` pair.homo / finding `BV-P2-HOMO`

### BV-P2-02 — NBSP no meio da key vs sem espaço → 2 Transfers

- **Sev:** P2 · **Lente:** BV4 · **Actor:** seller JWT
- **Pré:** NFKC mapeia U+00A0 → U+0020; o espaço **interior não é compactado**. Strip só `[\u200B-\u200D\uFEFF]` + `trim` nas pontas.
- **Repro:**
  1. POST `{amount:100, idempotency_key:"rtbvkey88"}`
  2. POST `{amount:100, idempotency_key:"rtbv\u00A0key88"}`
- **Esperado:** colapsar whitespace interior (mesma classe que ZWJ) **ou** 1 Transfer
- **Obtido:** 2 Transfers `tr_1UCcnMH7FWYUN3jhz7FqHU1y` + `tr_1UCcnOH7FWYUN3jhUCTbbDKe`; wallet 84.33 → 82.33 (−2,00 €)
- **Controlo:** `"rtbv k88x"` vs `"rtbv\u00A0k88x"` → **1** Transfer (`tr_1UCcnSH7FWYUN3jheUKSzQ5B`) — NFKC espaço HOLD
- **Impacto:** retry/cópia com NBSP no meio debita 2× o saldo do próprio vendedor. Não é mint.
- **Prova:** `pass1.json` pair.nbsp-none / `BV-P2-NBSP`; controlo `nbsp-space` BLOCKED

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Exact PUT | BV1 | 405 Method not allowed |
| Exact `amount:true` | BV4 | 400 Valor inválido |
| Exact `https://2130706433` | BV2 | 200 HTML wallet (sem Location 127.0.0.1) |
| `0177.0.0.1` / `0x7f000001` / `[::ffff:127.0.0.1]` | BV2 | 200 HTML wallet |
| evil.com, `@fleaber.pt`, `attacker.fleaber.pt`, IDN, cirílico host, nip.io, localtest.me, file: | BV2 | sem 303 hostil (HTML / 403 WAF) |
| Casefold `PayoutRtbv1` vs `payoutRtbv1` | BV4 | **2 Transfers** `tr_1UCcnAH7…` + `tr_1UCcnDH7…` Δ −2 € — **desenho** sem lowercasa; app `wd_uuid_…` |
| Race 3× mesma key | BV4 | 1 Transfer `tr_1UCcnWH7FWYUN3jhyLReJu7P` |
| crash_inject **sem** secret | BV4 | ignorado; payout 200 normal |
| crash_inject **com** secret + retry mesma key | BV4 | 500 debit órfão → retry 1 Transfer `tr_1UCcn2H7…` (não duplicou) |
| webhook `transfer.created` sem sig | BV4 | 400 `missing_signature` |
| webhook assinatura lixo | BV4 | 400 `invalid_signature` |
| `amount:[100]` / object / 100.5 / −100 / `0x64` / `1e2` | BV4 | 400 |
| `amount:"100"` / `100.0` | BV4 | aceite como 100 cêntimos (JS `Number.isInteger`) — desenho, 1 Transfer cada |
| body `destination`/`acct_fake` | BV6 | Transfer **própria** `tr_1UCcmkH7…` (destino cliente ignorado; fake acct teria falhado Stripe) — **FP pass1, não contar** |
| `user_id` buyer no body | BV6 | 400 Cannot create another user |
| JWT/anon `batata_wallet_payout_debit/finish` | BV6 | 403/401 GRANT |
| buyer JWT payout | BV6 | 400 Connect sem IBAN |
| buyer `refund-order` | BV3 | 403 Sem permissão |
| seller2 `refund-order` venda seller1 | BV6 | 403 |
| refund body `amount:999999` | BV3 | refund 590 cêntimos da linha (`already_refunded`/`idempotent`) |
| JWT `batata_finalize_stripe_order_refund` | BV6 | 403 GRANT service_role |
| buyer `pago`→`concluido` CTT / spoof mão | BV5 | 403 `order_concluido_requires_shipped` (`hand delivery`, `mão a mão`, `HANDS`, `entrega em m%`, …) |
| PATCH `shipping_method` pós-pago | BV5 | 403 `order_shipping_frozen_after_payment` |
| release JWT em `concluido` CTT sem `shipped_at` (estado forçado service) | BV3 | `false`, Δwallet 0 |
| unship após concluido real | BV5 | 403 `order_shipped_at_immutable`; status continua `concluido` (`pass3`) |
| pass2 `BV-P1-UNSHIP` | BV5 | **FP:** encomenda nunca saiu de `pago`; PATCH `pago` no mesmo estado 200 |
| release buyer após enviado→concluido | BV7 | `true`, Δ **+5,00 €** (crédito legítimo 5,90 − taxa); seller/buyer2 `false` |
| 2.º release | BV7 | Δ 0 |
| refund-order após enviado/concluido | BV3 | 403 `order_refund_blocked_shipped` |
| refund então release mão | BV3 | Δ 0 (sem crédito líquido) |
| race 3× refund-order | BV3 | idempotente mesmo `re_`; sem 2 capturas |

**Não é finding:** `service_role` a forçar `status=concluido` (fixture). Actor do exploit = JWT.

**Falsos positivos descartados:** `BV-P1-DEST` (Transfer para o Connect do JWT, body `destination` ignorado). `BV-P1-UNSHIP` no pass2 (nunca houve `concluido`).

**Contabilidade payout pass1:** wallet seller 93.33 → 80.33 = **−13,00 €** = 13 Transfers de 100 cêntimos (incl. pares lookalike). Sem mint.

---

## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| BV1 Connect/HTTP | SIM | HOLD PUT/PATCH 405 |
| BV2 return hijack | SIM | HOLD (exact decimal HTML; variantes novas sem 303 hostil) |
| BV3 release+refund | SIM | HOLD (buyer 403; residual; sem crédito pós-refund; refund blocked shipped) |
| BV4 Transfer/webhook | SIM | **P2 homóglifo + P2 NBSP**; race/crash/webhook HOLD |
| BV5 unship/FSM | SIM | HOLD concluido exige envio; shipped_at imutável |
| BV6 actor cruzado | SIM | HOLD user_id/seller2/finalize/debit JWT |
| BV7 Δwallet | SIM | payouts −13 € próprios; release +5 € só no ciclo enviado→concluido 1× |

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (debit/finish/finalize 403; 2.º release Δ=0)
13. Refund excede captura — NÃO (body 999999 → 590 cêntimos)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer indevidamente — PARCIAL: sim em keys lookalike (P2); não na mesma key (race/crash)
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
28. Saturação / último passe classe nova P0/P1 — NÃO (pass3 só HOLD)

ATROFIA (só exactos ZWJ/NFC/`amount:true`/PUT): NÃO  
Poço Stripe TEST pago: SIM (`setup_paid_order` + Transfers Connect TEST)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
