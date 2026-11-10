# FROZEN_REPORT — REDTEAM_BLIND_BJ_PAYOUT_POS_ATBE_v1

## CONTAGEM

P0 aberto: SIM          → quantos: 1
P1 aberto: SIM          → quantos: 1
P2 aberto: NÃO          → quantos: 0
P3 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 2

AUDITOR: REDTEAM_BLIND_BJ_PAYOUT_POS_ATBE_v1
FROZEN_AT: 2026-09-02T17:36:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BJ1, BJ2, BJ3, BJ4, BJ5, BJ6, BJ7]
VEREDICTO: FAIL_P0

Prefixo fixtures: `RTBJ-20260902T1822-`
Pasta: `tool/redteam_blind_bj_20260902T1822/`
Staging: `fxdknzrqjenzqcvnwqqq`
Stripe: TEST
Actors: anon · buyer JWT · seller JWT · buyer2 · seller2
service_role: só fixture / observação / cleanup

```
AUDITOR: REDTEAM_BLIND_BJ_PAYOUT_POS_ATBE_v1
production_touched: false · fase4: false · corrections_applied: false
```

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — SIM
2. Quantos P0: 1
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora de âmbito payout)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (`wallet_transactions` INSERT 42501; payout debit/finish 42501)
13. Refund excede captura — NÃO (body `amount=999999` → 590¢ = captura)
14. Release+refund cria dinheiro líquido — NÃO (refund pós-concluido 403 `order_refund_blocked_shipped`; clawback svc Δ=0)
15. Payout duplica Transfer — SIM (BJ4-01: NFC≠NFD = 2 `tr_`)
16. Stock=1 duas vendas válidas — NÃO (fora de âmbito)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (B/B2/S2 refund-order 403; B2 release false; user_id cruzado 400)
20. Cross-user dados sensíveis — NÃO (buyer GET `wallet_payout_ledger` do seller → `[]`)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (seller self-release false)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (debit/finish/clawback/finalize 42501)
25. RLS crítico quebrado — NÃO (PATCH wallets 200 `[]` sem mutação)
26. Edge confia total do cliente — PARCIAL (destination body ignorado; amount array/vírgula rejeitados; **idempotency_key sem NFC**)
27. Regressão funcional (happy path partido) — NÃO (`setup_paid_order` → enviado → concluido → release Δ=+5€; crash refund retry 1 `re_`)
28. Saturação atingida — SIM (7/7 lentes)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

**FAIL_P0.** Depois do fecho ATBE (POST-only + amount estrito), o levantamento ainda sai **duas vezes** se o cliente enviar a mesma chave visual em NFC e NFD. Cada pedido gera um `idempotency_key` SHA-256 distinto, dois débitos de carteira e duas Transfers Stripe TEST.

Há ainda um P1 de FSM: `batata_shipping_method_is_hand` usa `LIKE 'entrega em m%'|hand%|mao%`, por isso MB WAY com portes inventados (`entrega em morada`, `hand-ctt`) deixa o comprador marcar `concluido` sem `shipped_at`. O checkout Stripe **bloqueia** essas strings (allowlist exacta); não há mint de carteira plataforma (Δ=0). Não é o P0.

Exactos ATBE **não contados** (todos fechados): PUT/PATCH/DELETE 405; `amount:true`/`0x64`/`"1e2"` 400; hop `enviado` pós-refund `order_shipped_at_immutable`.

Anti-atrofia: achados = NFC/NFD (pedido no prompt) + release sem mão via LIKE (pedido no prompt). Exactos da lista ATBE = 0 de 5. Não é `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### BJ4-01 · P0 · BJ4 / BJ1 / BJ7 — idempotency_key NFC vs NFD = 2 Transfers

**O que isto é:** o vendedor pede um levantamento; a app manda uma chave de idempotência. Se a mesma palavra (`café`) for enviada em Unicode composto de duas formas, o servidor trata-as como pedidos **diferentes** e transfere o dinheiro duas vezes.

**Actor:** seller JWT · Edge `create-connect-account` · Stripe TEST Connect `acct_1U5mYbQeUNx8ar08`

**Pré:** Connect ready (`details_submitted` + transfers); saldo seller ≥ 2,00 €.

**Repro**
1. `POST /functions/v1/create-connect-account` JWT seller, `amount=100`, `idempotency_key="payout-café-bj22xx"` com `é` = U+00E9 (NFC).
2. Repetir com `idempotency_key="payout-café-bj22xx"` (`e` + U+0301, NFD). Visualmente idêntico; bytes distintos.
3. `Future.wait` das duas keys (pass3) confirma corrida.

**Esperado:** 2.º pedido idempotente — mesma Transfer, um só débito.

**Obtido (sequencial)**
- NFC → `200` `tr_1UBHzdH7FWYUN3jhscTAilDd` ledger `p_a9339d0b…` `balance_after=26`
- NFD → `200` `tr_1UBHzfH7FWYUN3jhgDTGv5BY` ledger `p_82d757cf…` `balance_after=25`
- Carteira seller: 27 → 26 → 25 (€1 + €1 saídos)

**Obtido (corrida pass3)**
- `tr_1UBI3RH7FWYUN3jhFoOejPyY` e `tr_1UBI3RH7FWYUN3jhABtrudnW` (dois ids)
- Saldo seller 21 → 19

**Porquê P0:** dinheiro Stripe TEST saiu duas vezes para a conta Connect do vendedor; irreversível no sentido Transfer. A Edge faz `payoutIdempotencyKey = SHA-256(userId + "\n" + rawKey)` **sem** `String.prototype.normalize('NFC')`. A mesma key ASCII (`${prefix}_race_samekey`) em `Future.wait` deu **uma** Transfer — o buraco é só Unicode.

**Não é o exacto ATBE** (`amount:true` / hex / `1e2`).

---

### BJ5-06 · P1 · BJ5 / BJ3 — `is_hand` LIKE largo → concluido sem envio (MB WAY)

**O que isto é:** a regra «só confirmar receção sem envio se for entrega em mão» aceita portes que **não** são mão (`entrega em morada`, `hand-ctt`, `mao CTT Expresso`, `entrega em mota`).

**Actor:** buyer JWT INSERT + seller JWT `pago` (MB WAY + `proof_url`) + buyer JWT `concluido`

**Repro**
1. `POST orders` JWT buyer, `shipping_method="entrega em morada"`, `payment_method="MB WAY"`, `price_total=7.2`.
2. Seller `PATCH status=pago` + `proof_url`.
3. Buyer `PATCH status=concluido` **sem** `enviado` / `shipped_at`.
4. `rpc batata_release_seller_wallet_for_order` JWT buyer → `true`.

**Esperado:** `order_concluido_requires_shipped`; release false.

**Obtido**
- Order `1de53c7f-904a-4406-b6d2-aa80cdd81073`: `status=concluido`, `shipped_at` null, release `200 true`, **Δ wallet seller = 0** (MB WAY fora da carteira plataforma).
- Variante `hand-ctt`: order `2a86639b-…` concluido 200 (mesma classe).
- `rpc batata_shipping_method_is_hand("entrega em morada")` → `200 true`.
- Stripe CPI com a mesma string → `400 Checkout blocked: portes da encomenda inválidos` (allowlist exacta na Edge). Checkout Seguro Fleaber **não** abre este atalho.

**Porquê P1 e não P0:** caminho REST explorável até FSM `concluido` + flag de release, mas **não** mint de saldo plataforma. O comprador é quem confirma; Flutter provavelmente não envia estas strings, mas JWT/REST é fronteira.

**Classe única** (não contar 5 P1): o mesmo `LIKE`.

--------------------------------------------------
## BLOQUEADOS (prova que ATBE / defesa segura)
--------------------------------------------------

| Lente | Prova | Resultado |
|-------|--------|-----------|
| BJ1 | PUT/PATCH/DELETE Connect | 405 |
| BJ1 | `amount` true / `0x64` / `"1e2"` / `[100]` / `"100,00"` / objecto | 400 inválido |
| BJ1 | `destination` / `user_id` alheio no body | Transfer própria ou 400 `Cannot create another user` |
| BJ1 | PATCH `wallets.stripe_account_id` JWT | 200 `[]`, conta `acct_1U5mYbQeUNx8ar08` inalterada |
| BJ1 | JWT `batata_wallet_payout_debit` / `_finish` | 42501 |
| BJ2 | GET `web_return_origin=https://evil.com` | HTML wallet, sem Location evil; `fleaber.pt/wallet?next=evil` → 303 `https://fleaber.pt/wallet` |
| BJ3 | Buyer/B2/S2 `refund-order` | 403 Sem permissão |
| BJ3 | JWT clawback / finalize refund | 42501 |
| BJ3 | `refund-order` body `amount=999999` em pago | 590¢ = captura |
| BJ3 | Release em `pago` sem envio (Stripe) | `false`; buyer `concluido` → `order_concluido_requires_shipped` |
| BJ3 | crash_inject refund `after_stripe_before_db` + retry | 1 `re_3UBI3TH7…`; release pós-refund `false` Δ=0 |
| BJ3 | Release + refund pós-`concluido` Stripe | refund 403 `order_refund_blocked_shipped`; clawback svc 5€ → Δ líquido 0 |
| BJ4 | crash_inject payout sem secret | ignorado (Transfer normal) |
| BJ4 | crash `after_debit_before_stripe` + retry mesma key | 1 `tr_1UBHzm…` |
| BJ4 | crash `after_stripe_before_finish` + retry | mesma `tr_1UBHzp…` |
| BJ4 | `Future.wait` mesma key ASCII | 1 Transfer |
| BJ4 | webhook `transfer.created` sem sig / sig forjada / GET | 400 / 400 / 405 |
| BJ5 | PATCH shipping após pago | `order_shipping_frozen_after_payment` |
| BJ5 | hop `enviado` após refund (exacto ATBE) | `order_shipped_at_immutable` |
| BJ6 | B2 release venda B1 | `false` |
| BJ6 | buyer lê ledger payout do seller | `[]` |
| BJ7 | JWT INSERT `wallet_transactions` | RLS 42501 |

Falsos positivos **não contados:** `amount` com NBSP → 100¢ correctos; PATCH unship em order **nunca enviada** (já `pago`, `shipped_at` null) → 200 no-op, depois cancelada pelo refund legítimo.

--------------------------------------------------
## LENTES
--------------------------------------------------

| # | Lente | Cobertura |
|---|--------|-----------|
| BJ1 | Connect/payout HTTP | SIM — amount hostil, dest spoof, JWT RPC, crash inject |
| BJ2 | return hijack | SIM — GET/POST origin evil / subdomain / javascript |
| BJ3 | release+refund | SIM — pago, pós-release, crash, clawback, MB WAY |
| BJ4 | Transfer dup/webhook | SIM — NFC/NFD, race, webhook, crash reconcile |
| BJ5 | unship/FSM | SIM — concluido sem mão, shipping freeze, hop refund |
| BJ6 | actor cruzado | SIM — B/B2/S2 refund, B2 release, user_id |
| BJ7 | Δwallet/Stripe net | SIM — payout −€ / release +5 / clawback 0 / refund 590¢ |

--------------------------------------------------
## PROVAS
--------------------------------------------------

- `tool/redteam_blind_bj_20260902T1822/pass1.json` (stdout + observe; dumpAll falhou no Set)
- `tool/redteam_blind_bj_20260902T1822/pass2.json`
- `tool/redteam_blind_bj_20260902T1822/pass2b.json`
- `tool/redteam_blind_bj_20260902T1822/pass3.json`
- `tool/redteam_blind_bj_20260902T1822/observe.dart` — wallet `acct_1U5mYbQeUNx8ar08` inalterada; ledger NFC/NFD
- Probes: `pass1.dart` `pass2.dart` `pass2b.dart` `pass3.dart` `_rtbj.dart`

Transfers P0 (Stripe TEST, não produção):
`tr_1UBHzdH7FWYUN3jhscTAilDd`, `tr_1UBHzfH7FWYUN3jhgDTGv5BY`, `tr_1UBI3RH7FWYUN3jhFoOejPyY`, `tr_1UBI3RH7FWYUN3jhABtrudnW`

Orders P1: `1de53c7f-904a-4406-b6d2-aa80cdd81073`, `2a86639b-2e2d-46ad-9dd3-6b5e777729af`

--------------------------------------------------
## LIMITAÇÕES
--------------------------------------------------

- Não se leram reports AX / BD / AR / AL (cegueira). Código/SQL/Edge sim.
- `crash_inject` só com secret de staging; o ponto existe mas o retry é idempotente (não é finding).
- Webhook `transfer.created` não está nos tipos tratados — replay assinado válido seria `ignored` (não provado sem `whsec`).
- Saldo seller TEST caiu 29 → 19 € pelos levantamentos de prova (incluindo o P0).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
