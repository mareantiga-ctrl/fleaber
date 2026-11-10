# FLEABER — RED TEAM CEGO DY · DEEP · PÓS-DNDS
## Composição multi-superfície — **quota ≥18 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> **Não** repetir só o fio DM/DS. Cada finding = **≥2 sítios**. Inventar cruzamentos novos.

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

Prefixo `RTDY-<timestamp>-` · pasta `tool/redteam_blind_dy_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**18** linhas LIVE.
2. Colunas: `probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD|FAIL|SKIP | classe_nova?`.
3. Linhas críticas: oráculo **≥2** de {Hub, orders, chat, live, wallet, products, CPI}.
4. **≥1** pago Stripe TEST no fio.
5. **≥5 races** composição (`Future.wait` distintas).
6. **≥4 probes** `classe_nova=SIM` (não hitch+Hub clássico sozinho).
7. Residual clássico ≥40% da tabela → **`ATROFIA_ABORT`** (proibido saturar).
8. Sem quota / sem 4 classes novas → `INCONCLUSIVO` / `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> O mesmo facto (pago, hold, published, rifa, tip, oferta) é **coerente** em todos os sítios **ou** o caminho perigoso está fechado.  
> Cruzar obrigatoriamente: rifa+bag+Hub · tip+payout+unpublish · oferta+bundle+Session · disputa+release+stock · follow+favorite+hold.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 linha cada — **não contar**)
--------------------------------------------------
Hub hide live accepted · Hub hide rifa drawn clássico (qty=1) · MB WAY exact 400 · 4∥2 / 5∥3 ≤1 cs_ · follow published 403 · buyer refund 403

≥40% tabela = estes HOLD → **`ATROFIA_ABORT`**.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥18)
--------------------------------------------------

### DY-A Hub ↔ money (≥5)
A1 unpublish mid-checkout **e** mid-tip (+ payout se possível)  
A2 sold+listed vs Hub vs insert  
A3 leftover após pago parcial (qty 2→1)  
A4 favorite + hold qty=1 + 2.º buyer  
A5 rifa drawn + Hub + insert (reteste 1 linha se Hub 0; se Hub 1 = HOLD finding)

### DY-B Live ↔ marketplace **novo** (≥5) — classe_nova
B1 accept hitch SKU-A + bag SKU-B (outro artigo mesmo seller)  
B2 convert + chat card + Hub + order  
B3 end_live∥bag CPI∥Hub refresh  
B4 rifa draw∥marketplace CPI no mesmo SKU (paralelo)  
B5 live_only prize (sem product_id) vs Hub leak

### DY-C Chat / oferta / bundle (≥4)
C1 oferta aceite + CPI underpay (`total_eur`/`amount` hostil) — selo servidor  
C2 Future.wait bundle∥single overlap mesma linha  
C3 chat card amount vs `orders.amount_paid` após pago  
C4 seller/buyer PATCH status `pago` sem Stripe

### DY-D Race caixa (≥4)
D1 refund∥nova compra leftover  
D2 release∥disputa  
D3 2 buyers Hub visível + insert/CPI qty=1  
D4 **pago 4242** → Hub + order + wallet Δ + chat (4 sítios no mesmo print/oracle)

**Total mínimo = 18.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
DY1 hub · DY2 live · DY3 chat · DY4 wallet · DY5 race · DY6 offer · DY7 rifa · DY8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥18 · ≥4 classe_nova · ≥5 races · 1 pago · multi-sítio coerente · P0–P2=0 → `PASS_CEGO_SATURADO`.  
Sem 4 classe_nova → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N · classes_novas: N · races: N
stripe_test_pago: true|false
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
