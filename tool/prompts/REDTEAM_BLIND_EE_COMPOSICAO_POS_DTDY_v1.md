# FLEABER — RED TEAM CEGO EE · DEEP · PÓS-DTDY
## Composição multi-superfície — **quota ≥18 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Cruzar fechos DTDY (bag + rifa + revoke + release∥disputa) em **≥2 sítios** por finding. Inventar cruzamentos novos — não só DY clássico.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco do FROZEN (INVÁLIDO sem números N)
--------------------------------------------------
**Obrigatório:** `quantos` = 0,1,2… · TOTAL = P0+P1+P2+P3 · ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`

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

**No fim do FROZEN (obrigatório):**
`RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`

Prefixo `RTEE-<timestamp>-` · pasta `tool/redteam_blind_ee_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**18** linhas LIVE.
2. Colunas: `probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD|FAIL|SKIP | classe_nova?`.
3. Linhas críticas: oráculo **≥2** de {Hub, orders, chat, live, wallet, products, CPI, storage}.
4. **≥1** pago Stripe TEST no fio.
5. **≥5 races** composição.
6. **≥4 probes** `classe_nova=SIM`.
7. Residual clássico ≥40% → **`ATROFIA_ABORT`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> O mesmo facto (pago, hold, rifa, tip, oferta, disputa, bag Session) é **coerente** em todos os sítios **ou** o caminho perigoso está fechado.  
> Cruzar: rifa+bag+Hub · release∥disputa+stock · expand bag+Hub leftover · revoke+disputa+chat · tip+payout+unpublish.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 linha cada — **não contar**)
--------------------------------------------------
Hub hide live accepted · Hub hide rifa drawn qty=1 · MB WAY exact 400 · 4∥2 ≤1 cs_ open · follow published 403 · buyer refund 403 · release∥disputa 1 efeito (1 linha)

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥18)
--------------------------------------------------

### EE-A Hub ↔ money (≥5)
A1 unpublish mid-checkout **e** mid-tip  
A2 sold+listed vs Hub vs insert  
A3 leftover após pago parcial (qty 2→1)  
A4 favorite + hold qty=1 + 2.º buyer  
A5 rifa drawn + Hub + live_item ≠ available (reteste)

### EE-B Live ↔ marketplace **novo** (≥5)
B1 accept hitch SKU-A + bag SKU-B  
B2 convert + chat card + Hub + order  
B3 end_live∥bag CPI∥Hub refresh  
B4 rifa draw∥marketplace CPI mesmo SKU  
B5 **6∥4 bag** + Hub stock após 1 pago (composição DT)

### EE-C Chat / oferta / dispute storage (≥4)
C1 oferta aceite + CPI underpay  
C2 Future.wait bundle∥single overlap  
C3 release∥disputa + chat card + wallet  
C4 revoke proof mid-disputa + proof_ok + UI path

### EE-D Race caixa (≥4)
D1 refund∥nova compra leftover  
D2 2 buyers Hub + CPI qty=1  
D3 **pago 4242** → Hub + order + wallet + chat (4 sítios)  
D4 expand bag subset→superset + settle só na Session final open

**Total mínimo = 18.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
EE1 hub · EE2 live · EE3 chat · EE4 wallet · EE5 race · EE6 bag · EE7 rifa · EE8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥18 · ≥4 classe_nova · ≥5 races · 1 pago · multi-sítio coerente · P0–P2=0 → `PASS_CEGO_SATURADO`.  
Sem 4 classe_nova → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_EE_COMPOSICAO_POS_DTDY_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N · classes_novas: N · races: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
