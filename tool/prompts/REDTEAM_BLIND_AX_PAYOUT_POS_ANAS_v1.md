# FLEABER — RED TEAM CEGO AX
## Auditor independente · PÓS-FECHO ANAS · PAYOUT / WALLET / REFUND · v1

> Fechámos ANAS payout/FSM: buyer **não** `concluido` em devolução (`order_concluido_denied_during_return`); seller **não** marca entregue/concluido; `shipped_at` **imutável** (unship → 403); release exige envio ou mão; idempotency payout **hash SHA-256** (não slice 64). Hostile ANAS + AL/AHAM PASS.  
> **Poço saída de dinheiro:** payout, Transfer, refund, release — ainda sai 2× ou mint?  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST (pagar 4242 se P0), cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

Ver também `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: N
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P3` ou `PASS_CEGO_SATURADO` se 7/7 lentes saturadas
- P0–P3 fechados (TOTAL = 0) → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST.  
Produção proibida · Fase 4 não.  
Prefixo: `RTAX-<timestamp>-`.  
`service_role` só fixture / observação.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Dinheiro na carteira/Connect — consigo tirar 2×, para conta errada, ou refund/release que minta?**

Não repetir exactos AR/AL:
- buyer concluido during return exact AR7 (agora 403 — testar seller concluido, cron 48h, partial release)
- unship silent 200 exact AR5 (agora immutable — testar status regression, shipped_at via service_role leak)
- idempotency prefix 64 exact AR-P3-01 (agora hash — testar collision, replay key curta, 2 users mesma key)
- cancel silent 200 AL5 · dual Session · mint pós-payout

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta AR/AL → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AX (obrigatório 7/7)
--------------------------------------------------
| # | Lente |
|---|--------|
| AX1 | Payout JWT/Edge hostil · replay idempotency hash |
| AX2 | Connect return hijack |
| AX3 | Release + refund + clawback = líquido |
| AX4 | Transfer duplicado / webhook replay |
| AX5 | Seller refund após release · parcial > captura · devolvida gate |
| AX6 | Buyer força refund alheio · cancel pós-pago · FSM return |
| AX7 | Composição até Δwallet / Stripe net |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 fluxo Stripe TEST **pago** + release ou refund.  
2. Percorrer devolução → tentar concluir/refund/devolvida cruzados.  
3. Contabilidade: buyer wallet · seller wallet · Stripe.  
4. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_ax_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** + **TOTAL** no topo.

```
AUDITOR: REDTEAM_BLIND_AX_PAYOUT_POS_ANAS_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AX1, AX2, AX3, AX4, AX5, AX6, AX7]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas — igual AT).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
