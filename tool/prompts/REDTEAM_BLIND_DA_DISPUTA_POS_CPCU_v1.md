# FLEABER — RED TEAM CEGO DA · DEEP · PÓS-CPCU
## Disputa / path / canonical — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Path exacto 1 ficheiro; sem 54000. Não chase triple-encode exacto CDCI.

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
1. P0? SIM|NÃO  2. Quantos P0: N
3. P1? SIM|NÃO  4. Quantos P1: N
5. P2? SIM|NÃO  6. Quantos P2: N
7. P3? SIM|NÃO  8. Quantos P3: N
```

Prefixo `RTDA-<timestamp>-` · pasta `tool/redteam_blind_da_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | URL/payload | HTTP/RPC | BD/stock | HOLD|FAIL|SKIP`.
3. **≥1** happy path disputa + prova própria. Controlo `%252f%255c` ≤1 se HOLD — não contar.
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Canonical limpo **sem 54000**. Prova própria OK. Concat/`//`/traversal → deny.  
> Bypass path **novo** (não só `%252f%255c` exacto CU).

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: `%252f%255c` · `%25252e` · ZWSP dots · PaysafeCash.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### DA-A Canonical / happy (≥3)
A1 RPC canonical URL limpa → sem 54000  
A2 disputa + PNG próprio → 201  
A3 label URL limpa

### DA-B Path hostil (≥5)
B1 controlo `%252f%255c` concat → deny  
B2 **novo** slash mix / unicode slash / backslash encode  
B3 `..` / double-encode residual  
B4 bucket public / prova B2 alheia  
B5 label evil / relativo

### DA-C FSM / stock / refund (≥4)
C1 2.ª disputa 409  
C2 FSM buyer/seller  
C3 stock restore no refund (não ×2)  
C4 buyer refund 403; release com disputa

**Total mínimo = 12.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DA1 canonical · DA2 54000 · DA3 happy · DA4 path · DA5 FSM · DA6 stock · DA7 refund

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A* OK · B* deny · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DA_DISPUTA_POS_CPCU_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
