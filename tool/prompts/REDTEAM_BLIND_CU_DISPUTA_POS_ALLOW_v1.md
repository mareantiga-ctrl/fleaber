# FLEABER — RED TEAM CEGO CU · DEEP · PÓS-ALLOWLIST
## Disputa / provas / path — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Validar allowlist/canonical: URL limpa **sem** 54000; happy path OK; path attack ainda denied.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL + checklist 1–8)
--------------------------------------------------
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

Prefixo `RTCU-<timestamp>-` · pasta `tool/redteam_blind_cu_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | URL/payload | HTTP/RPC | BD/stock | HOLD|FAIL|SKIP`.
3. **≥1** happy path disputa completo. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> URL/path **canónico limpo** → **sem** erro 54000.  
> Happy path disputa funciona.  
> Ataques de path (`%255c`, traversal, etc.) **continuam denied**.  
> Atacar allowlist/canonical — não chase triple-encode exacto.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: PaysafeCash · PicPay · esaurito · Coptic · follow unpublished.  
Residual path CDCI exacto ≤2. ≥50% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### CU-A Canonical limpo (≥3)
A1 prova/foto URL **canónica limpa** (https, path normal) → **sem 54000**  
A2 label URL canónica limpa → OK  
A3 open disputa + upload prova canónica → FSM avança

### CU-B Happy path (≥3)
B1 abrir `pedido_devolucao` / disputa em order elegível  
B2 buyer + seller passos mínimos até estado estável  
B3 stock/refund coerente no happy path (medir BD)

### CU-C Path attack ainda denied (≥4)
C1 `%255c` / mixed encode → deny  
C2 `..\` / null `%00` filename → deny  
C3 bucket swap / prova order B em disputa A → deny  
C4 label host evil / relative hostil → deny

### CU-D Residual FSM/refund (≥2)
D1 2.ª disputa / partial qty  
D2 buyer refund Seguro hostil / release∥disputa

**Total mínimo = 12.** FAIL se A1 der 54000 em URL limpa; FAIL se C* aceitar path hostil.

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
CU1 canonical · CU2 54000 · CU3 happy path · CU4 path deny · CU5 FSM · CU6 stock · CU7 refund

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · A1 sem 54000 · B* OK · C* denied · P0–P2 = **0** → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CU_DISPUTA_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
