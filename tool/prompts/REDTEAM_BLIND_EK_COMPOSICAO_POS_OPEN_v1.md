# FLEABER — RED TEAM CEGO EK · DEEP · POS_OPEN_MVP
## Composição multi-sítio — **quota ≥18** · **GATE FINAL abertura**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Último portão: saco + Hub + wallet + chat + rifa coerentes. Se EK P0/P1 → **não abrir**.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números N)
--------------------------------------------------

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

`RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`

Prefixo `RTEK-<timestamp>-` · pasta `tool/redteam_blind_ek_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**18**.
2. Oráculo **≥2 sítios** por finding.
3. **≥5 races** · **≥4 classe_nova** · **≥1 pago 4242**.
4. **Obrigatório** reteste 6∥4 + expand no fio composição (com Hub).
5. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Um facto (pago, hold, rifa, bag Session, disputa) coerente em Hub/orders/chat/wallet/live **ou** caminho fechado.  
> Gate: **sem** dual Session open no bag; **sem** oversell; **sem** crédito+disputa.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Hub hide accepted · rifa Hub 0 clássico · 4∥2 · buyer refund 403 · MB WAY exact

--------------------------------------------------
## MATRIZ (≥18)
--------------------------------------------------

### EK-A Hub ↔ money (≥5)
A1 unpublish mid-checkout + tip  
A2 leftover pós-pago  
A3 favorite+hold+2.º  
A4 rifa + live_item ≠ available  
A5 sold vs Hub vs insert

### EK-B Bag gate (≥4) — classe_nova
B1 **6∥4** + Hub leftover  
B2 **expand** subset→superset  
B3 bag∥single + Hub  
B4 bag pago único → 4 sítios (Hub/order/chat/wallet)

### EK-C Live / oferta / disputa (≥5)
C1 hitch A + bag B  
C2 oferta underpay selo  
C3 release∥disputa + chat + wallet  
C4 revoke mid-disputa + proof_ok  
C5 rifa∥CPI

### EK-D Race final (≥4)
D1 2 buyers qty=1  
D2 refund∥leftover  
D3 end_live∥bag∥Hub  
D4 **pago 4242** 4 sítios

**Total ≥18.**

--------------------------------------------------
## GATE ABERTURA
--------------------------------------------------
`PASS_CEGO_SATURADO` aqui **e** EF/EG sem P0–P2 → candidato a **abrir a todos**.  
Qualquer P1 bag dual open → **NÃO ABRIR**.

```
AUDITOR: REDTEAM_BLIND_EK_COMPOSICAO_POS_OPEN_v1
probes_na_tabela: N · classes_novas: N · races: N
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
