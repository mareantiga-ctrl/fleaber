# FLEABER — RED TEAM CEGO BO
## Auditor independente · PÓS-FECHO BFBK · HUB / EDGE / MUX / TIP · v1

> Fechámos BFBK: `hub_lives_discovery_public` VOD só `ended`; web_return rejeita IP decimal/`127.1`; anon sem `batata_live_is_broadcasting`. Hostile BFBK PASS.  
> **Poço:** ainda VOD prematuro, tip bypass, CORS/Connect?  
> Staging · TEST · **não corrigir**.

## CONTAGEM (obrigatório — ANTES de findings)
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = relatório INVÁLIDO.

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
**Sem TOTAL → INVÁLIDO.** O fecho começa sempre por colar esta CONTAGEM no chat.

Prefixo `RTBO-<timestamp>-` · `tool/redteam_blind_bo_<timestamp>/`.

## MISSÃO
> Depois do fecho discovery/CDN BFBK, ainda assisto VOD sem Edge ou tiro tip?

**Exactos BI/BC (não contar):** discovery scheduled+VOD · `web_return` 2130706433 · tip `No such checkout`.  
**Novas:** IPv6 mapped · DNS rebinding host · FOMO RPC · handle_suggested · embed keys · resolve-mux estados · tip unpaid B2 · CORS · storage · complete-mux cruzado · outra view pública com playback · tabela `lives` directa.

## LENTES BO (7/7)
BO1 Hub/FOMO · BO2 origin/CORS/Connect · BO3 tip settle · BO4 Edge body · BO5 Mux/LiveKit · BO6 storage · BO7 composição.

Não ler BI/BC/AW.

```
AUDITOR: REDTEAM_BLIND_BO_HUB_EDGE_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
