# FLEABER — RED TEAM CEGO DC · DEEP · PÓS-CVDA
## Chat notes / label / inbox — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> CW saturado. Allowlist estrita — só canónicos. Bypass residual fino.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco do FROZEN (INVÁLIDO sem números N)
--------------------------------------------------
**Obrigatório:** `quantos` = 0,1,2… · TOTAL = P0+P1+P2+P3 · ver `REDTEAM_CONTAGEM_OBRIGATORIO.md`

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

Prefixo `RTDC-<timestamp>-` · pasta `tool/redteam_blind_dc_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**14** linhas.
2. Colunas: `probe_id | superfície | payload | HTTP/RPC | BD/inbox | HOLD|FAIL|SKIP`.
3. Residual `12,00` / `doze euros` ≤2 se HOLD — não contar.
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Canónicos OK. Tudo o resto deny. Bypass: case/ZWSP/homoglyph **em canónico**, type coercion, inbox.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: `12,00` · `doze euros` · PaysafeCash · PicPay.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DC-A Positivos (≥3)
A1 vazio · A2 `stripe_paid_direct` · A3 `obrigado` / `já enviei`

### DC-B Bypass (≥7)
B1 canónico + ZWSP/NBSP  
B2 case (`Paguei`) / acento  
B3 canónico + sufixo (`ok por favor`)  
B4 texto livre não canónico («tudo bem») → deny  
B5 JSON / number type  
B6 RTL / tags / zero-width só  
B7 inbox PATCH hostil

### DC-C Seguro + FSM (≥4)
C1 label Seguro hostil vs canónico  
C2 card hostil  
C3 PATCH `pago` sem Stripe  
C4 storage alheio (1)

**Total mínimo = 14.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DC1 allowlist · DC2 encoding · DC3 inbox · DC4 seguro · DC5 card · DC6 FSM · DC7 Edge

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A* OK · B* deny · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DC_CHAT_POS_CVDA_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
