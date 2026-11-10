# FLEABER — RED TEAM CEGO BU
## Auditor independente · PÓS-FECHO BLBQ · HUB / EDGE / MUX / TIP · v1

> Fechámos BLBQ Hub: `lives` anon **sem** colunas Mux VOD; Hub items anon 200; `resolve_handle` unpublished sem live → not_found; `web_return` IP decimal **cru**. Hostile BLBQ PASS.  
> **Poço:** ainda VOD prematuro noutro canal, tip bypass, CORS/Connect?  
> Staging · TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = INVÁLIDO.

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N

1. P0? SIM|NÃO   2. Quantos P0: N
3. P1? SIM|NÃO   4. Quantos P1: N
5. P2? SIM|NÃO   6. Quantos P2: N
7. P3? SIM|NÃO   8. Quantos P3: N
```
**Sem TOTAL → INVÁLIDO.**

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBU-<timestamp>-` · `tool/redteam_blind_bu_<timestamp>/`.

> Depois do fecho Hub/CDN BLBQ, ainda assisto VOD sem Edge ou tiro tip?

**Exactos BO/BI (não contar):** `GET lives` + `mux_vod_playback_id` anon · `https://2130706433` · resolve `handle_suggested` loja vazia · discovery scheduled+VOD.  
**Novas:** IPv6 mapped (`[::ffff:127.0.0.1]`) · `127.0.0.1.nip.io` / DNS rebind · embed `lives(*)` noutro REST · `mux_playback_id` em live **inactive** via view alternativa · tip unpaid B2 · CORS Origin · storage buckets públicos · `complete-mux` cruzado · FOMO snapshot `is_active=false`.

--------------------------------------------------
LENTES BU (7/7)
--------------------------------------------------
BU1 Hub/FOMO · BU2 origin/CORS/Connect · BU3 tip settle · BU4 Edge body · BU5 Mux/LiveKit · BU6 storage · BU7 composição.

Não ler BO/BI/BC/AW.

```
AUDITOR: REDTEAM_BLIND_BU_HUB_EDGE_POS_BLBQ_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
