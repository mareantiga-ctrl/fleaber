# FLEABER — RED TEAM CEGO DJ · DEEP · PÓS-DBDG
## Live stock / hitch / convert / rifa — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> FOMO allowlist DBDG. Aqui: **stock real, reservas, convert, rifa** — não chase FOMO.

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

Prefixo `RTDJ-<timestamp>-` · pasta `tool/redteam_blind_dj_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**14** linhas.
2. Colunas: `probe_id | poço | payload | RPC/HTTP | stock/BD | HOLD|FAIL|SKIP`.
3. Controlo welcome OK (1). Residual FOMO `voou tudo` ≤1 se HOLD — não contar.
4. **≥1** race hitch/accept/end.
5. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Stock live **não** oversell. Convert **só** com PI pago próprio.  
> Rifa/follow tickets só published. Welcome allowlist OK; FOMO free-text deny.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: welcome · `voou tudo` deny · `🔥` deny · follow unpublished.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DJ-A FOMO allowlist controlo (≥3)
A1 welcome OK + Hub  
A2 «directo a começar» OK  
A3 FOMO free-text / emoji urgência → deny (1 residual)

### DJ-B Stock / hitch (≥5)
B1 2 buyers hitch mesma unidade  
B2 hitch qty > available  
B3 accept ∥ reject paralelo  
B4 end_live ∥ accept  
B5 reserve após ended

### DJ-C Convert / rifa / Mux (≥6)
C1 convert sem PI  
C2 convert PI alheio / outra live  
C3 convert após unpublish  
C4 rifa tickets follow unpublished vs published  
C5 playback unpublished buyer  
C6 tip mid-live residual (1)

**Total mínimo = 14.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
DJ1 welcome · DJ2 FOMO deny · DJ3 hitch · DJ4 stock · DJ5 convert · DJ6 rifa · DJ7 race · DJ8 Mux

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥14 · sem oversell · convert locked · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DJ_LIVE_STOCK_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
