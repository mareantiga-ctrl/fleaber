# Pack cego POS_OPEN_MVP — DEEP (EF→EK) · porta aberta a sellers reais

**Objectivo do pack:** provar que o **cadeado do saco** e o dinheiro à volta estão fechados o suficiente para **abrir a toda a gente** (não só 1–2 amigos).  
P0–P2 **têm** de ficar a 0. P3 resolve-se. P4 fora de âmbito.

**Porquê agora:** residual crítico = dual Session no overlap (bug de shadow `bagClaimToken` + corridas). Off-platform multibanco/ifthenpay fechado. 4/6 do pack anterior saturaram — este pack **não é frouxo**.

**Já fechado (HOLD ≤1 linha — não contar):**  
claim token no write (sem shadow) · orphan expire overlap · denylist multibanco/ifthenpay/COD · rifa live_item sold · revoke JWT 403 · proof_ok registry · release∥disputa clawback · Edge settle clássico

## Critério “pronto a abrir”

`PASS_CEGO_SATURADO` em **EF + EG** (saco) + **EK** (composição dinheiro) com P0=P1=P2=0  
**e** nenhum P0/P1 nos outros.  
Se EF/EG ainda tiverem P1 dual-`cs_` open/payable → **NÃO ABRIR**.

## Regra de saturação

- Quota cumprida · ≥4 `classe_nova` · races pedidas · ≥1 Stripe TEST pago onde a matriz pede  
- Zero findings **sem** 4 classes novas → `ATROFIA_ABORT`  
- Oráculo Session: contar `cs_` **open** + settle; 2× HTTP 200 com **mesmo** `cs_` + `reused=true` = OK (não finding)

## ⚠️ CONTAGEM — 1.º bloco de CADA FROZEN (INVÁLIDO sem números N)

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0 dinheiro irreversível? SIM|NÃO
2. Quantos P0: N
3. P1 caminho explorável? SIM|NÃO
4. Quantos P1: N
5. P2 hygiene? SIM|NÃO
6. Quantos P2: N
7. P3 baixo risco? SIM|NÃO
8. Quantos P3: N
```

No fim: `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`  
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

## Os 6 (completos)

| # | Ficheiro | Superfície | Quota | Papel p/ abertura |
|---|----------|------------|-------|-------------------|
| 1 | `tool/prompts/REDTEAM_BLIND_EF_BAG_MUTEX_POS_OPEN_v1.md` | Saco / mutex / overlaps | ≥22 | **Gate** dual Session |
| 2 | `tool/prompts/REDTEAM_BLIND_EG_BAG_PAY_POS_OPEN_v1.md` | Saco + tentar pagar 2× | ≥14 | **Gate** P0 dinheiro |
| 3 | `tool/prompts/REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1.md` | Off-platform / métodos | ≥16 | Denylist + App OK |
| 4 | `tool/prompts/REDTEAM_BLIND_EI_STOCK_HUB_POS_OPEN_v1.md` | Stock / Hub sob stress | ≥16 | Oversell |
| 5 | `tool/prompts/REDTEAM_BLIND_EJ_WALLET_EDGE_POS_OPEN_v1.md` | Wallet + Edge pós-pago | ≥16 | Dinheiro após pago |
| 6 | `tool/prompts/REDTEAM_BLIND_EK_COMPOSICAO_POS_OPEN_v1.md` | Multi-sítio abertura | ≥18 | Gate final |

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **não**.
