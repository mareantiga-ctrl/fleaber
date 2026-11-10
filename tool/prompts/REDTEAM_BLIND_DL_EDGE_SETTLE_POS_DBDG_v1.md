# FLEABER — RED TEAM CEGO DL · DEEP · PÓS-DBDG
## Edge settle / tip / refund / webhook — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Dinheiro na **Edge**. ≥1 Transfer ou refund ou tip Session TEST.

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

Prefixo `RTDL-<timestamp>-` · pasta `tool/redteam_blind_dl_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD|FAIL|SKIP`.
3. **≥1** operação dinheiro TEST real (pago/refund/tip Session/transfer).
4. Buyer refund seller-only → documentar 403.
5. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Settle/webhook **não** confia total do cliente.  
> Tip amount/`tip_id` autoridade servidor.  
> Refund idempotente; race refund∥release sem double credit.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: buyer refund 403 · Coptic payout key · charset 400.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### DL-A Settle / Session (≥4)
A1 settle unpaid GET  
A2 settle com session_id alheio  
A3 metadata amount vs servidor  
A4 reuse Session após expire

### DL-B Tip (≥3)
B1 tip amount hostil / tip_id cliente  
B2 tip mid-unpublish unpaid  
B3 tip seller≠owner

### DL-C Refund / release / Connect (≥5)
C1 buyer `refund-order` → 403  
C2 seller refund idempotente (2×)  
C3 refund∥release race  
C4 Connect idempotency key hostil  
C5 overbalance / dest alheio

**Total mínimo = 12.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DL1 settle · DL2 tip · DL3 refund actor · DL4 idempotency · DL5 race · DL6 Connect · DL7 Δwallet

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · ≥1 dinheiro TEST · actors OK · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DL_EDGE_SETTLE_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.** Seller-only refund: reportar só se abriu.
