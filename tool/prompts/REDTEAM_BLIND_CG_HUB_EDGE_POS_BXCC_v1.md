# FLEABER — RED TEAM CEGO CG · DEEP
## Auditor independente · PÓS-FECHO BXCC · HUB / EDGE / MUX / TIP / STORAGE · v1-deep

> Fechámos BXCC: `batata_resolve_handle` + discovery só `hub_published`; Mux cols revoke auth. Hostile PASS.  
> **DENSO:** discovery + tip + CORS/origin + Edge Mux + storage na mesma corrida.  
> Staging · TEST · **NÃO CORRIGIR** · Fase 4 **não**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
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
**Sem TOTAL → INVÁLIDO.**

Prefixo `RTCG-<timestamp>-` · `tool/redteam_blind_cg_<timestamp>/`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Ainda vejo **loja/live/stock desligados**, **tiro tip sem pagar**, **abuso Edge/CORS**, ou **Mux/storage alheio** — além do exacto unpublished resolve?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar exactos: resolve unpublished clássico · discovery unpublished · SELECT mux_playback JWT buyer já residual.  
Conta: tip unpaid · complete-mux hostil · CORS/IPv6 return · storage Hub · dono JWT vs anon bypass errado · stock Hub vs PostgREST.

--------------------------------------------------
## POÇOS OBRIGATÓRIOS (≥4)
--------------------------------------------------

### POÇO CG-A — HUB DISCOVERY / PRIVACY (matriz)
1. `hub_published=false` via **todas** as entradas: resolve_handle · views `hub_*` · RPC search · deep link slug · follow/favorite  
2. live activa + hub off (política actual = published-only — tentar bypass)  
3. stock/preço Hub vs tabela base (ler montra morta / soft-delete)  
4. reviews/opiniões de loja não publicada  
5. 2.º actor: anon vs buyer vs seller dono

### POÇO CG-B — TIP / PAGAMENTO LEVE
1. tip settle JWT buyer; `stripe_session_id` cliente; amount body  
2. tip unpaid → crédito seller / notificação “pago”  
3. tip bind a live/order alheia  
4. replay tip webhook / return

### POÇO CG-C — EDGE / ORIGIN / MUX
1. Connect/Hub return URL: CORS · Origin spoof · IPv6 · localhost · `null` origin  
2. `resolve-mux` / `complete-mux` / create live: JWT alheio · anon · seller ≠ owner  
3. stream keys / playback via Edge response leak  
4. Edge bloqueia mas INSERT/SELECT directo PostgREST passa (ou o contrário)

### POÇO CG-D — STORAGE / COMPOSIÇÃO
1. avatars / hub media path traversal · list alheio  
2. Encadear: discovery leak → tip ou Mux → dado ou dinheiro indevido

--------------------------------------------------
## LENTES CG (≥5/7)
--------------------------------------------------
CG1 Hub · CG2 origin/CORS · CG3 tip · CG4 Edge · CG5 Mux · CG6 storage · CG7 composição

--------------------------------------------------
## TÁCTICAS MÍNIMAS
--------------------------------------------------
1. Matriz discovery ≥4 entradas (não só resolve).  
2. ≥1 tip ou settle tentativa hostil.  
3. ≥1 Edge Mux/origin.  
4. ≥1 composição ou storage.  
5. Evidência HTTP status + body + BD.

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Poços A–D · lentes ≥5 · tácticas 1–4 · senão `INCONCLUSIVO`.

```
AUDITOR: REDTEAM_BLIND_CG_HUB_EDGE_POS_BXCC_v1
production_touched: false · fase4: false · corrections_applied: false
VEREDICTO: FAIL_P0|FAIL_P1|FAIL_P2|FAIL_P3|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```

**NÃO CORRIGIR.**
