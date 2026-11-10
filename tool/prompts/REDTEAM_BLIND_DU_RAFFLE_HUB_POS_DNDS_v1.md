# FLEABER — RED TEAM CEGO DU · DEEP · PÓS-DNDS
## Rifa / Hub / stock / convert / hitch — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DNDS: seal ao `drawn` + hold winners. **Provar** Hub/CPI/live_item coerentes; atacar falhas de selagem e multi-winner.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO` · `REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTDU-<timestamp>-` · pasta `tool/redteam_blind_du_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. Oráculo multi-sítio em findings: Hub + products + live_item + orders (± CPI).
3. **≥1** draw real com bilhetes + **≥1** pago Stripe noutro fio (ou no mesmo arco).
4. **≥4 classe_nova**.
5. **≥3 races** (draw∥CPI, award∥unlist, convert∥accept).
6. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Após `drawn`: prémio **não** fica comprável no Hub; hold impede insert; live_item não fica `available` como se nada.  
> Encomenda `premio_rifa` desejável; se falhar, seal/hold **ainda** fecham a montra.  
> Atacar: winner_count>1, product qty>1, rifa sem live_item, draw 2×, forge winner JWT, partilhar sem rifa.

--------------------------------------------------
## ANTI-ATROFIA (HOLD — não contar)
--------------------------------------------------
Hub hide live accepted clássico · FOMO deny · welcome OK · drawn seal qty=1 clássico se Hub 0 (1 linha reteste)

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### DU-A Draw / seal (≥5)
A1 draw qty=1 marketplace hitch → Hub 0 + insert deny (reteste 1 linha se OK)  
A2 draw com **winner_count=2** e stock=2 → Hub qty efectiva / 2.º insert  
A3 draw **sem** `product_id` (live_only) → documentar skipped vs leak  
A4 draw 2× idempotente (2.º already/deny)  
A5 JWT buyer tenta `batata_draw_live_raffle_winners`

### DU-B Stock cross (≥4)
B1 award tickets + draw∥CPI marketplace paralelo  
B2 after drawn: CPI / insert order nova  
B3 leftover stock=3 winners=1 → Hub ainda lista? qty  
B4 refund/cancel premio_rifa (se existir) vs Hub restore

### DU-C Convert / hitch / rifa social (≥4)
C1 convert pending sem pago → deny  
C2 accept hitch + rifa mesmo SKU  
C3 partilhar **sem** rifa activa → sem bilhetes  
C4 partilhar **com** rifa → elegível + forge entry alheia

### DU-D Caixa (≥3)
D1 **pago 4242** SKU não-prémio + Hub leftover  
D2 prize_orders[] vs seal.ok no retorno draw  
D3 live_item status após draw (sold/reserved ≠ available)

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DU1 draw · DU2 Hub · DU3 hold · DU4 race · DU5 multi-winner · DU6 forge · DU7 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · ≥3 races · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DU_RAFFLE_HUB_POS_DNDS_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
