# FLEABER — RED TEAM CEGO DG · DEEP · PÓS-CVDA
## Disputa / path / prova — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> CVDA: `//` só após host — prova signed **deve** 201. Concat continua deny.

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

Prefixo `RTDG-<timestamp>-` · pasta `tool/redteam_blind_dg_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | URL/payload | HTTP/RPC | BD/stock | HOLD|FAIL|SKIP`.
3. **≥1** happy path disputa **com** prova signed própria → **201** (obrigatório).
4. Controlo `%252f%255c` deny ≤1 se HOLD — não contar.
5. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Canonical sem 54000. Prova+label signed própria OK. Concat/traversal deny.  
> Bypass path **novo** (não exacto DA `%252f%255c`).

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: prova signed 201 · `%252f%255c` deny · `%25252e` · ZWSP dots.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### DG-A Happy / canonical (≥3) — **obrigatório feliz**
A1 RPC canonical limpa sem 54000  
A2 `POST` disputa + proof signed própria → **201**  
A3 PATCH `return_label_url` signed própria → 200

### DG-B Path hostil (≥5)
B1 controlo `%252f%255c` → deny  
B2 unicode slash / backslash **novo**  
B3 `..` / double-encode  
B4 bucket public / prova B2  
B5 label evil / relativo / scheme-less

### DG-C FSM / stock / refund (≥4)
C1 2.ª disputa 409  
C2 FSM buyer/seller  
C3 stock restore refund  
C4 buyer refund 403; release com disputa

**Total mínimo = 12.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DG1 canonical · DG2 54000 · DG3 happy prova · DG4 path · DG5 FSM · DG6 stock · DG7 refund

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A2+A3 OK · B* deny · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DG_DISPUTA_POS_CVDA_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
