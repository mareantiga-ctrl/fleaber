# FLEABER — RED TEAM CEGO DR · DEEP · PÓS-DHDM
## Tip / rifa / convert / Edge live money — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Dinheiro e stock **no directo**: tip Session, rifa, convert reservation→order.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTDR-<timestamp>-` · pasta `tool/redteam_blind_dr_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**14**.
2. **≥1** tip Session ou convert ou rifa com efeito BD (Stripe TEST se tip pago).
3. **≥3 races** live (accept∥CPI, convert∥convert, tip∥unpublish).
4. **≥3 classe_nova**.
5. FOMO text allowlist residual = HOLD máx 1 linha (não encher tabela).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Tip: amount/`tip_id` servidor; unpaid não credita.  
> Rifa: só elegíveis; partilhar sem rifa ≠ prémio.  
> Convert: capacidade; sem double order; hitch stock coerente Hub/CPI.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
FOMO deny sinónimo · welcome OK · tip mid-unpublish unpaid clássico · buyer refund 403

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DR-A Tip Edge (≥4)
A1 tip amount hostil no body  
A2 tip_id / live_id alheio  
A3 tip∥end_live  
A4 tip seller≠live owner

### DR-B Rifa (≥3)
B1 partilhar **sem** rifa activa → sem prémio  
B2 partilhar **com** rifa → elegível  
B3 winner forge JWT / double assign

### DR-C Convert / hitch (≥5)
C1 convert pending→order qty  
C2 convert∥convert 2 buyers  
C3 accept∥marketplace CPI qty=1  
C4 convert após live ended  
C5 converted capacity vs stock

### DR-D Caixa (≥2)
D1 tip Session TEST (ou skip documentado se tip off)  
D2 convert feliz + order ledger

**Total = 14.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DR1 tip auth · DR2 rifa · DR3 convert · DR4 race · DR5 stock · DR6 unpublish · DR7 Edge

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥14 · ≥3 classe_nova · ≥3 races · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
