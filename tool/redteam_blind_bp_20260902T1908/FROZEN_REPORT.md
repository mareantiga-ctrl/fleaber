# FROZEN_REPORT — RED TEAM CEGO BP

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido: NÃO)

TOTAL P0–P3 abertos: 1
```

**VEREDICTO:** `FAIL_P2`

```
AUDITOR: REDTEAM_BLIND_BP_PAYOUT_POS_BFBK_v1
FROZEN_AT: 2026-09-02T19:15:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BP1, BP2, BP3, BP4, BP5, BP6, BP7]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Transfers reais `tr_1UBI…` na conta Connect do vendedor lab) · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Prefixo `RTBP-20260902T1908-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

BJ/BD/AX **não lidos**. Poço: 2 Transfers / mint ledger / refund·release mentiroso depois do fecho mão/NFC.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora do poço payout; amount array/hex/1e2/frac rejeitados)
10. Buyer manipula qty autoritativa — NÃO (não exercido checkout)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (PATCH wallets `[]`; INSERT 42501; debit/finish RPC 42501)
13. Refund excede captura — NÃO (body `amount` ignorado; PI fake → Stripe `No such payment_intent`; sem inflação)
14. Release+refund cria dinheiro líquido — NÃO (`refund-order` pós-concluido 403 `order_refund_blocked_status`; buyer wallet refund em `pago` = `false`, Δ=0)
15. Payout duplica Transfer — PARCIAL (NFC=NFD 1 Transfer; race mesma key 1 Transfer; crash retry 1 Transfer; **NFKC/ZWJ/case/fullwidth = 2 Transfers = P2 classe única**)
16. Stock=1 duas vendas válidas — NÃO (fora de poço)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (`user_id` alheio 400; B1 release order B2 `false`; buyer `refund-order` 403; B2 refund wallet `false`)
20. Cross-user dados sensíveis — NÃO (não exercido Hub)
21. Buyer assume seller/admin — NÃO (Connect `user_id` S2 400; buyer payout sem IBAN 400)
22. Seller assume buyer/admin — NÃO (seller não marca `concluido`; clawback/finalize 42501)
23. Reviews forjadas — NÃO (fora de poço)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`payout_debit`/`finish`/`clawback`/`finalize`/`ensure_wallet` 42501 JWT/anon)
25. RLS crítico quebrado — NÃO (wallets sem UPDATE/INSERT JWT)
26. Edge confia total do cliente — NÃO (`destination` extra ignorado; `crash_inject` sem secret ignorado; `amount` não-inteiro rejeitado) — **parcial:** hash idempotency só NFC
27. Regressão funcional (happy path partido) — NÃO (auditor não alterou código)
28. Saturação atingida — NÃO (hash unicode still open; PI Stripe real para over-refund não exercido)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Exactos BJ/AX da lista do prompt — **não redescobertos como findings** (e não contam):

| Exacto (não contar) | Resultado |
|---------------------|-----------|
| NFC vs NFD (`café`) | BLOCKED — `tr_1UBIdVH7FWYUN3jhOcljLZJX` nas duas; 2ª `idempotent:true` |
| `entrega em morada` LIKE | BLOCKED — RPC `false`; PATCH concluido 403 `order_concluido_requires_shipped` |
| PUT Transfer | BLOCKED — 405 |
| `amount:true` | BLOCKED — 400 inválido |

Baseline pack (não contar): `web_return` IP decimal — staging **ainda** 303 `https://127.0.0.1/wallet` (`GET ?web_return_origin=https://2130706433`). Repo local tem `isSuspiciousHostname`; Edge de staging aparentemente sem esse guard. **Exacto — fora da CONTAGEM.**

Outros fechados (não exactos, não contar): PATCH/DELETE 405; `user_id` alheio 400; `amount:[100]` / object / `1e2` / `0x64` / `100.5` 400; JWT debit/finish 42501; PATCH wallets não persiste; INSERT wallets 42501; evil.com / userinfo / subdomain / file: / javascript: sem Location hostil; BOM prefix → mesma Transfer; Future.wait mesma key → 1 Transfer; `crash_inject` sem secret ignorado; crash+retry mesma key → 1 Transfer; handmade / cyrillic / fullwidth / nbsp / `entrega em m` / CTT / FedEx não são mão; shipping freeze pós-pago; INSERT concluido → `reserva_pendente`; release em `pago` `false`; B1≠buyer `false`; buyer/B2 `refund-order` 403; finalize/clawback 42501; webhook sem sig / sig lixo / GET.

Atrofia da lista exacta: **0** findings contados. Não `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### P2-BP4 — `payoutIdempotencyKey` só `normalize('NFC')`; NFKC / ZWJ / casefold / fullwidth = 2 Transfers

**Lentes:** BP4, BP7, BP1

**O que isto é:** o fecho BFBK colapsa NFC=NFD (`café` pré-composto vs combinante) para **uma** Transfer. O hash continua a ser `SHA-256(userId + NFC(trim(raw)))`. Formas **compatibility** ou caracteres invisíveis **não** colapsam. Cada variante é uma intenção nova: dois débitos de 1,00 € e duas Transfers Stripe, se o saldo chegar.

**Não é P0/P1:** o JWT do dono da carteira já pode levantar N vezes com N keys até ao saldo. A app gera `wd_{uuid}_{cents}_{ms}` (sem ligaduras). Δwallet bateu certo (16 € → desceu 1 € por Transfer). O risco residual é retry/copy-paste que mude compatibility/invisíveis — a mesma família unicode que o P0 NFC, **por fechar**.

**Actor:** seller JWT (conta Connect pronta `acct_1U5mYbQeUNx8ar08`)

**Pré:** saldo ≥ 2,00 €; `isConnectReady`.

**Repro:**
```
POST /functions/v1/create-connect-account
{ "amount": 100, "idempotency_key": "<A>" }
POST … mesma amount, key <B> NFKC/ZWJ/case/fullwidth-equivalente
```

**Esperado:** 2ª resposta `idempotent` + o **mesmo** `transferId` (ou rejeição), como NFC=NFD.

**Obtido (classe única — 4 encodings):**

| Par | Key A vs B | Transfer A | Transfer B |
|-----|------------|------------|------------|
| NFKC ﬁ vs fi | `…_nfkc_fidempkey` vs `…_nfkc_ﬁdempkey` | `tr_1UBIdZH7FWYUN3jhcYUleECR` | `tr_1UBIdcH7FWYUN3jhp2DDkdsz` |
| ZWJ U+200D | `…_zwjbasexxxx` vs `…_zwj\u200dbasexxxx` | `tr_1UBIdkH7FWYUN3jhTigmFodG` | `tr_1UBIdmH7FWYUN3jhp8MeDMPj` |
| casefold | `…_CaseFoldK` vs `…_casefoldk` | `tr_1UBIdpH7FWYUN3jhEBABGfih` | `tr_1UBIdsH7FWYUN3jhOYGV9fX4` |
| fullwidth ｆｗ | `…_fwkeyxxxx` vs `…_ｆｗkeyxxxx` | `tr_1UBIdvH7FWYUN3jhqAYYz0WB` | `tr_1UBIdxH7FWYUN3jhylCi0x9v` |

BOM U+FEFF no prefixo → **mesma** Transfer (`tr_1UBIdfH7FWYUN3jhxkW2BF4u`, 2ª `idempotent`) — `trim()` come o BOM.

NFC=NFD (não contar) → `tr_1UBIdVH7FWYUN3jhOcljLZJX` nas duas.

**Porque P2:** dual Transfer Stripe comprovado; raiz única (`NFC` sem NFKC/strip Cf/casefold). Não minta além do saldo. Flutter não gera estas variantes no retry.

--------------------------------------------------
## BLOQUEADOS (amostra)
--------------------------------------------------

| Prova | Resultado |
|-------|-----------|
| PUT/PATCH/DELETE connect | 405 |
| `user_id` B1 no JWT S1 | 400 another user |
| `destination` / `stripe_account_id` extra | Transfer criada na **própria** conta (campos ignorados) |
| `amount:[100]` / `{cents:100}` / `"1e2"` / `"0x64"` / `100.5` / `true` | 400 |
| JWT/anon `batata_wallet_payout_debit` / `finish` | 42501 |
| PATCH wallets `stripe_account_id`+`balance` | 200 `[]`; acct inalterado |
| INSERT wallets S2 | 42501 |
| GET return `evil.com` / `evil@fleaber.pt` / `attacker.fleaber.pt` / `file:` / `[::1]` | sem Location hostil |
| GET `ﬂeaber.pt` (ligature) | 303 `https://fleaber.pt/wallet` (host real) |
| Future.wait mesma key | 1 Transfer `tr_1UBIe0H7FWYUN3jh0BjGefYe` |
| `crash_inject` sem secret | payout 200 (ignorado) |
| crash `after_debit_before_stripe` + retry | 500 depois 200 **mesmo** fluxo; 1 Transfer `tr_1UBIe6H7FWYUN3jhgBhMMAJZ` |
| crash `after_stripe_before_finish` + retry | mesmo `tr_1UBIe9H7FWYUN3jh1wcMx17N` |
| handmade / hand-to-hand / hаnd / ｈａｎｄ / `hand\u00a0` / `entrega em m` / CTT / FedEx | RPC `false`; concluido 403 |
| `hand` / `entrega em mão` | RPC `true`; pago→concluido 200 (desenho mão) |
| CTT→hand após pago | 403 `order_shipping_frozen_after_payment` |
| INSERT JWT `status=concluido` | gravado `reserva_pendente` |
| release em `pago`+`shipped_at` | `false` |
| B1 release order B2 | `false`; seller release `false` |
| buyer / B2 `refund-order` | 403 Sem permissão |
| `refund-order` `amount:999999` | não inflou; PI fake 500 Stripe |
| `finalize` / `clawback` JWT | 42501 |
| `refund_buyer_wallet` em `pago` | `false`; Δ buyer 61.10→61.10 |
| B2 refund wallet B1 | `false` |
| `refund-order` após concluido | 403 `order_refund_blocked_status` |
| webhook sem sig / sig lixo / GET | 400 / 400 / 405 |
| `batata_ensure_wallet` B1→S2 | 42501 |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Coberta | Nota |
|-------|---------|------|
| BP1 Connect/HTTP | SIM | só POST; amount hostil rejeitado |
| BP2 return hijack | SIM | evil/userinfo/sub/file/js/IPv6 fechados; IP decimal exacto ainda no Edge (não contar) |
| BP3 release+refund | SIM | sem mint em pago; refund-order bloqueado pós-concluido; buyer wallet sem mint fora de `devolvida` |
| BP4 Transfer/webhook | SIM | P2 unicode hash; race/crash/BOM/webhook ok |
| BP5 unship/FSM | SIM | allowlist exacta; freeze portes; INSERT concluido rebaixado |
| BP6 actor cruzado | SIM | user_id, refund, release, RPC debit, ensure |
| BP7 Δwallet | SIM | 1 € por Transfer; crash retry sem 2º débito extra; refund wallet Δ=0 |

--------------------------------------------------
## LACUNAS HONESTAS
--------------------------------------------------

- Sem `sk_test` no env do auditor: não listei Transfers na API Stripe (só IDs devolvidos pela Edge + ledger). Destino Connect inferido pelo código (`destination: accountId` da carteira JWT).
- Over-refund vs captura **com PI real** não exercido (evitar anular vendas lab alheias). Código: `amount` não está no body; `Math.min(rowPaid, remaining, …)`.
- Fixture `service_role` INSERT `concluido`+hand+PI fake → buyer `release` mintou 6,05 € (desenho do RPC quando o estado já é `concluido`). JWT **não** consegue INSERT nesse estado. Não é finding de actor.

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------

Lentes 7/7. Exactos BFBK reproduzidos e fechados. Nova classe unicode no hash de levantamento **aberta** (P2). Não `PASS_CEGO_SATURADO`.

Probes: `tool/redteam_blind_bp_20260902T1908/pass1.dart`, `pass2.dart`.
