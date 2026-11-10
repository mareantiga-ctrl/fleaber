# FROZEN_REPORT — REDTEAM_BLIND_FC_DISPUTE_EDGE_SMOKE_PRE_P4_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? NÃO
4. Quantos P1: 0
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0

```
AUDITOR: REDTEAM_BLIND_FC_DISPUTE_EDGE_SMOKE_PRE_P4_v1
FROZEN_AT: 2026-09-07T09:31:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 11
classes_novas: 11
races: 3
stripe_test_pago: true
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 aplicada nesta corrida · **sem patches**.  
Prefixo: `RTFC-20260907T0924-` · pasta: `tool/redteam_blind_fc_20260907T0924/`.  
Atacante JWT B1 `bfcbeeee-…` / S1 `980f4fa1-…` + B2 fresco `c150d6e5-…` / S2 `6bbab42c-…`. `service_role` só fixture / observação / restore / mark enviado-concluido / end_live.

GATE FC: P0–P2=0 → `PASS_CEGO_SATURADO`. Double credit / forge webhook que credita = P0. Pack FA+FB+FC completo **não** declarado aqui (só lente FC).

---

## Anti-atrofia

Exactos **não corridos / não contados**:
- tip seller≠owner — **não** na tabela
- Coptic charset — **não** contar

Fechos (HOLD = ataque bloqueado / esperado):
- **A1** release∥disputa t=0 → rel `true` + disputa `201` · venda 5 + estorno 5 **net=0** claim aberto `both=false`
- **A2** disputa-first →50 ms→ release → disputa `201` · release `false` · **venda=0** open **both=false**
- **A3** disputa após `enviado` → **DENY** 403 RLS `order_disputes` · Δwallet=0
- **B1** buyer refund-order → **403** `Sem permissão.`
- **B2** seller 2× mesma order → **1** `re_3UCxwZH7FWYUN3jh1TjrXSAQ`
- **B3** GET settle unpaid **402** · POST **400** metadata · `reserva_pendente` Δ=0
- **B4** session alheia GET **402** · POST **200** **nova** `cs_` oidB · A/B `reserva_pendente` (sem liquidar sidA)
- **D1** refund∥release → **1** `re_3UCxwlH7…` · release `false` · Δ=0 net=0
- **C1** tip unpaid GET **200** copy unpaid · tip `pending` Δ=**0**
- **C2** webhook sem sig **400** `missing_signature` · sig morta **400** `invalid_signature`
- **C3** CORS Origin `https://evil.com` → ACAO `https://fleaber.pt` (echoes=[])

HOLD na tabela = **11/11 = 100%** bloqueios; residual clássico **não** na quota. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A1, A2, A3, B1, B2, B3, B4, D1, C1, C2, C3 (**11**).

---

## Findings abertos

Nenhum. P0=0 P1=0 P2=0 P3=0.

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | FC-A | Future.wait release ∥ disputa t=0 oid `68f7aafa-…` PI `pi_3UCxwNH…` | rel **200** `true` · disp **201** `59d78378-…` | venda=5 estorno=5 **net=0** open=1 `both=false` | HOLD | SIM |
| A2 | FC-A | disputa-first →50 ms→ release oid `f1a3c59b-…` PI `pi_3UCxwRH…` | disp **201** `dd4c6049-…` · rel **200** `false` | venda=0 net=0 open=1 `both=false` | HOLD | SIM |
| A3 | FC-A | POST disputa após `enviado` oid `d528b8a6-…` PI `pi_3UCxwVH…` | **403** 42501 RLS `order_disputes` | janela **DENY** st=`enviado` Δ=0 | HOLD | SIM |
| B1 | FC-B | refund-order JWT comprador oid `423749d6-…` | **403** Sem permissão | — (seller refund a seguir) | HOLD | SIM |
| B2 | FC-B | seller refund 2× mesma order | 200 `idempotent` ×2 | **1** `re_3UCxwZH7FWYUN3jh1TjrXSAQ` | HOLD | SIM |
| B3 | FC-B | GET/POST settle unpaid `cs_test_a1k6U8zm…` oidA `4a529423-…` | GET **402** · POST **400** metadata | `reserva_pendente` Δ=0 | HOLD | SIM |
| B4 | FC-B | sidA (B2) JWT B1 + CPI inject oidB | GET **402** · POST **200** nova `cs_test_a1HoXqnS…` · CPI **400** | A/B `reserva_pendente` | HOLD | SIM |
| D1 | FC-B | refund ∥ release oid `fb7f0dfa-…` PI `pi_3UCxwlH…` | ref **200** `re_3UCxwlH7…` · rel **false** | Δ=0 net=0 st=`cancelado` | HOLD | SIM |
| C1 | FC-C | tip unpaid GET settle `cs_test_a1AnnaTz…` tip `cd1a04ba-…` | POST **200** · GET **200** copy unpaid | `pending` Δ=**0** | HOLD | SIM |
| C2 | FC-C | stripe-webhook sem sig + v1=deadbeef livemode | **400** missing · **400** invalid | sem side-effect | HOLD | SIM |
| C3 | FC-C | OPTIONS+POST Origin=`https://evil.com` CPI/refund | ACAO `https://fleaber.pt` ×4 | echoes=[] | HOLD | SIM |

probes_na_tabela: **11** (A1–A3 · B1–B4 · D1 · C1–C3). Quota ≥10.

`classe_nova=SIM`: **11**.  
Races: A1, A2, D1 → **3**.

Dinheiro Stripe TEST real: **sim** — 5 PI succeeded (`pi_3UCxwNH…`, `pi_3UCxwRH…`, `pi_3UCxwVH…`, `pi_3UCxwZH…`, `pi_3UCxwlH…`); 2 refunds (`re_3UCxwZH7FWYUN3jh1TjrXSAQ`, `re_3UCxwlH7FWYUN3jh1B80c0DV`). Tip Session unpaid `cs_test_a1AnnaTz…` **não** capturada.

Directo da corrida terminado (`is_active=false`). Hub S1 restaurado.

**Não é finding:** B4 POST 200 devolveu **nova** Checkout Session (`cs_test_a1HoXqnS…`) sem liquidar sidA nem oidB. C1 GET tip unpaid **200** copy «ainda não confirmado» sem crédito.

---

## Missão

Pós-pago e Edge de caixa continuam à prova de corrida e forge. Um efeito por intenção.

**Resposta:** **Missão fechada.** release∥disputa 0 ms venda+estorno **net=0** claim aberto; 50 ms dispute-first **venda=0** open **both=false**. Disputa em `enviado` **DENY** 403. Buyer refund **403**. Seller 2× **1** `re_`. Settle unpaid GET **402** / POST **400** Δ=0. Session alheia não paga outra order. Tip unpaid Δ=0. Webhook forge **400**. CORS não ecoa `evil.com`. refund∥release Δ=0. Double credit **não**. Forge webhook que credita **não**.

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. release∥disputa t=0 crédito líquido + claim — NÃO (clawback net=0)
10. release∥disputa t=50 crédito líquido + claim — NÃO (só disputa)
11. disputa após `enviado` mintou — NÃO (DENY 403)
12. Buyer refund-order aberto — NÃO (403)
13. Seller refund 2× duplica `re_` — NÃO (1 id)
14. settle unpaid credita — NÃO (402/400 Δ=0)
15. settle session alheia liquida outra order — NÃO
16. tip unpaid GET settle Δwallet — NÃO (pending Δ=0)
17. webhook sem assinatura credita — NÃO (400)
18. CORS ecoa Origin evil — NÃO (`fleaber.pt`)
19. refund∥release crédito líquido — NÃO (Δ=0)
20. Saturação P0–P2=0 após quota ≥10 + ≥3 classe_nova + ≥1 race release∥disputa — SIM

Lacuna honesta: captura 4242 da Checkout Session de **tip** não (sem `sk_test_` local). Pack FA+FB **não** corrido nesta pasta — OK Fase 4 do pack exige os 3.

---

## INVARIANTES

- 1 efeito por intenção (release∥disputa / 2× refund / settle unpaid).
- Buyer nunca refund.
- Session unpaid / alheia nunca mint.
- Tip unpaid Δwallet=0.
- Webhook sem `whsec` não tem side-effect.
- CORS allowlist não ecoa origin hostil.

```
AUDITOR: REDTEAM_BLIND_FC_DISPUTE_EDGE_SMOKE_PRE_P4_v1
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
