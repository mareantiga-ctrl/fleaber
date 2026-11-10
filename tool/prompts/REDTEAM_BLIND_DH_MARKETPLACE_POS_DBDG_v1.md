# FLEABER — RED TEAM CEGO DH · DEEP · PÓS-DBDG
## Marketplace / saco / mutex / preço / stock — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DBDG: mutex buyer + write `cs_` só com claim próprio. **Atacar a fundo** — não rails.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco do FROZEN (INVÁLIDO sem números N)
--------------------------------------------------
**Obrigatório:** `quantos` = 0,1,2… · TOTAL = P0+P1+P2+P3 · ver `REDTEAM_CONTAGEM_OBRIGATORIO.md`

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

Prefixo `RTDH-<timestamp>-` · pasta `tool/redteam_blind_dh_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**16** linhas LIVE (uma por tentativa).
2. Colunas: `probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD|FAIL|SKIP`.
3. **≥3 races** `Future.wait` distintas.
4. **≥1** Stripe TEST **pago** (4242) + contabilidade order/stock.
5. Sem quota → `INCONCLUSIVO` (proibido saturar).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Mutex + claim: **≤1** Session útil em overlap; 2.º = contention/reuse/expire órfã.  
> Off-platform non-ASCII → sem Stripe. Preço/stock: underpay e oversell **não** passam.  
> Ângulos **novos** (não exacto 4∥2 residual se HOLD).

--------------------------------------------------
## ANTI-ATROFIA (≤2 linhas HOLD — não contar)
--------------------------------------------------
4∥2 se ≤1 cs_ · `mbωay`/`𝗺𝗯𝘄𝗮𝘆` · `mb way` exact 400 · PaysafeCash

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### DH-A Claim / mutex (≥4)
A1 reclaim `cs_` morta + 2.º actor  
A2 claiming futuro / malform / TTL  
A3 crash mid-claim + retry  
A4 mutex: 2 CPI mesmo buyer bags disjuntos em paralelo (comportamento documentar)

### DH-B Overlap races (≥5) — **obrigatório**
B1 bag **4∥2** (esperado ≤1 cs_ útil / contention)  
B2 bag **3∥1**  
B3 bag∥**single** mesma linha  
B4 2 buyers última unidade  
B5 checkout ∥ unlist / qty=0

### DH-C Preço / off-platform / pago (≥5)
C1 underpay `total_eur` / item hostil  
C2 portes / coupon com Session open  
C3 off-platform **novo** encode (não exacto DB)  
C4 `transferência` legítima → off (400 Stripe)  
C5 **1× pago 4242** + stock/caixa

### DH-D Cross (≥2)
D1 bag cross-seller → deny  
D2 qty hostil / stock claim

**Total mínimo = 16.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
DH1 Session · DH2 mutex · DH3 bag∥ · DH4 stock · DH5 preço · DH6 off-platform · DH7 race · DH8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥16 · ≥3 races · 1 pago · B* ≤1 cs_ útil · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DH_MARKETPLACE_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
