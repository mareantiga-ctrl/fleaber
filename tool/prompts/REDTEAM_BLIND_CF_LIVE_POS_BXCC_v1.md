# FLEABER — RED TEAM CEGO CF · DEEP
## Auditor independente · PÓS-FECHO BXCC · LIVE / STAFF / FOMO / MUX · v1-deep

> Fechámos BXCC: FOMO «last one»/«já não há»/«sem stock»; `mux_playback_id` revoke auth. Hostile PASS.  
> **DENSO:** matriz FOMO + hitch + race end∥accept + Mux/helper na mesma corrida.  
> Staging · TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> **BATATA live:** podes provar via RPC/Edge/BD; não pedes redesign do player/Arena no relatório como “fix”.

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

Prefixo `RTCF-<timestamp>-` · `tool/redteam_blind_cf_<timestamp>/`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Ainda anuncio **compra/FOMO falsa**, **converto sem PI**, **leio Mux/stream alheio**, ou **parto stock no hitch** — fora dos exactos BZ/BXCC?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar exactos: «last one» · «já não há» · «sem stock» · mux_playback buyer JWT SELECT clássico · paused FOMO PT/EN já HOLD.  
≥50% só residual → `ATROFIA_ABORT`.

--------------------------------------------------
## POÇOS OBRIGATÓRIOS (≥4)
--------------------------------------------------

### POÇO CF-A — FOMO / CHAT LIVE (matriz)
Testar **≥10** variantes (PT/EN/ES/emoji/l33t). Exemplos a cobrir na corrida:
- emoji-only: «🔥1 left🔥» · «⚠️sold⚠️» · «✅taken»
- l33t / spaced: «l a s t   o n e» · «s0ld» · «já  não   há»
- sinonímia nova: «esgotou» · «foi embora» · «já tem dono» · «mine now» · «claiming» · «no more left» · «acaba de sair»
- homógrafos / bidi dentro de «sold» / «reservado»
- staff vs buyer: quem pode emitir; buyer imita staff

FAIL se: UI/outros buyers crêem venda · stock desce · convert sem pagamento.

### POÇO CF-B — CONVERT / PI / STAFF
1. convert sem PaymentIntent / Session  
2. convert com PI de outra live / outro buyer  
3. helper/mod perms: promover-se; kick; OCR; anunciar sold  
4. qty hitch: reservar N>stock; race 2 hitch mesma unidade

### POÇO CF-C — RACE / FSM LIVE
1. `end_live` ∥ `accept` / convert / bag add  
2. live ended mas RPC ainda vende  
3. gravado/VOD path vs live activa (ID swap)

### POÇO CF-D — MUX / STREAM / PRIVACY
1. playback ID via views Hub / RPC / Edge `resolve-mux` com JWT alheio / anon  
2. stream key / room token leak (SELECT, Edge, logs)  
3. dono vs viewer: owner bypass legítimo ≠ buyer lê alheio

### POÇO CF-E — COMPOSIÇÃO CAIXA
FOMO/convert mentiroso → order `pago` / stock / Stripe. Obrigatório ≥1 cadeia.

--------------------------------------------------
## LENTES CF (≥6/8)
--------------------------------------------------
CF1 convert · CF2 FOMO · CF3 stock · CF4 hitch · CF5 qty · CF6 race · CF7 Mux · CF8 caixa

--------------------------------------------------
## TÁCTICAS MÍNIMAS
--------------------------------------------------
1. Matriz FOMO ≥10 strings.  
2. ≥1 race end∥accept ou 2 hitch.  
3. ≥1 Mux/stream tentativa pós-revoke.  
4. ≥1 convert sem PI ou PI alheio.  
5. Evidência BD (+ Stripe se dinheiro).

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Poços A–E · ≥6 lentes · tácticas 1–4 · senão `INCONCLUSIVO`.

```
AUDITOR: REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1
production_touched: false · fase4: false · corrections_applied: false
VEREDICTO: FAIL_P0|FAIL_P1|FAIL_P2|FAIL_P3|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```

**NÃO CORRIGIR.**
