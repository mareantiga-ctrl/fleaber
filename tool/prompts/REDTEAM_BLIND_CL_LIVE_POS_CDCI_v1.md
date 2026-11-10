# FLEABER — RED TEAM CEGO CL · DEEP v2 · PÓS-FECHO CDCI
## Live / FOMO / staff / hitch — **quota ≥24 FOMO + 4 poços**

> Staging · TEST · **NÃO CORRIGIR**. BATATA: sem redesign player/Arena.  
> Ronda CF trouxe só 3 P2 — **agora matriz FOMO obrigatória estilo CE**.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL)
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

Prefixo `RTCL-<timestamp>-` · `tool/redteam_blind_cl_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS` ≥30 linhas**.
2. **≥24** FOMO/`batata_live_system_message` (lista abaixo — todas).
3. **≥1** staff self-promote · **≥1** hitch∥convert race · **≥1** Mux/realtime/playback probe · **≥1** end∥accept.
4. Controlo residual CDCI (`last one`, `foi embora`) ≤3 linhas.
5. Sem quota → **`INCONCLUSIVO`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> FOMO multi-língua, staff falso, hitch/convert, playback fora do revoke exacto?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
FOMO compact PT-EN CDCI · sender_label Sistema · playback_id revoke clássico. Residual só.

--------------------------------------------------
## MATRIZ FOMO — ≥24 (todas via RPC system message + buyer GET)
--------------------------------------------------
**IT (6):** ultimo pezzo · esaurito · già venduto · non c’è più · preso · e s a u r i t o  
**DE (6):** letztes Stück · ausverkauft · schon weg · kein Lager · verkauft · a u s v e r k a u f t  
**FR (6):** dernier article · épuisé · plus de stock · déjà pris · vendu · e p u i s e (spaced)  
**Extra (6):** 🛑1 left · going going gone · final call · quase a acabar · ultimo disponibile · nur noch einer  

FAIL = `ok:true` + row `kind=system` visível a buyer (sem convert pago).

### CL-B Staff (≥3)
B1 buyer INSERT staff/helper row  
B2 escalate `can_manage_chat` self  
B3 helper zero-perms anuncia FOMO

### CL-C Hitch / convert / race (≥4)
C1 hitch qty>stock  
C2 convert sem PI  
C3 convert PI alheio  
C4 end_live ∥ accept/hitch

### CL-D Mux / realtime (≥3)
D1 realtime channel payload playback  
D2 resolve-mux unpublished (controlo)  
D3 SELECT colunas irmãs novas se existirem

--------------------------------------------------
## LENTES ≥6/8
--------------------------------------------------
CL1 convert · CL2 FOMO · CL3 stock · CL4 hitch · CL5 qty · CL6 race · CL7 Mux · CL8 caixa

```
AUDITOR: REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1
probes_na_tabela: N (≥30)
VEREDICTO: …
```
**NÃO CORRIGIR.**
