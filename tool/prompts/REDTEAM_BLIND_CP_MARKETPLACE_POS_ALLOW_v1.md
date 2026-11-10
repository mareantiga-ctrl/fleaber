# FLEABER — RED TEAM CEGO CP · DEEP · PÓS-ALLOWLIST
## Marketplace / checkout / saco — **quota ≥12 probes** (ataque allowlist + dinheiro/stock)

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> CJ→CO fechados. **Não** chase sinónimos de rails. Missão = **bypass / buracos** da allowlist + regressão claim/saco.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL + checklist 1–8)
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

Prefixo `RTCP-<timestamp>-` · pasta `tool/redteam_blind_cp_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Secção **`## TABELA DE PROVAS`** no FROZEN: **≥12 linhas** (uma por tentativa LIVE).
2. Colunas: `probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD|FAIL|SKIP`.
3. **≥2 races** `Future.wait` distintas (linhas na tabela).
4. **≥1** checkout Stripe TEST **pago** (4242) + contabilidade order.
5. Sem isto → **`INCONCLUSIVO`** (proibido `PASS_CEGO_SATURADO`).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Atacar a **nova allowlist** e residual de dinheiro/stock: bag overlap 4∥2, reclaim `cs_` morta, claiming futuro — **não** listas de rails.

--------------------------------------------------
## ANTI-ATROFIA (não contar exactos se HOLD)
--------------------------------------------------
PaysafeCash · PicPay · esaurito · Coptic · follow unpublished (já fechados).  
≥50% só residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12 — cada item ≥1 linha)
--------------------------------------------------

### CP-A Claim / Session / cs_ (≥5)
A1 reclaim Session Stripe **morta** (`cs_` expirada / cancelada) — 2.º actor ou retry  
A2 claiming com **timestamp futuro** (`claiming:<ms_futuro>`)  
A3 claiming malformado / sem ms / ms passado extremo  
A4 Session expire mid-checkout → 2.ª Session mesma order  
A5 crash/timeout mid-claim + retry idempotente

### CP-B Bag overlap / race (≥4) — **obrigatório 4∥2**
B1 **bag 4-line ∥ bag 2-line** overlap parcial mesmo SKU (race)  
B2 2 buyers última unidade `Future.wait`  
B3 checkout ∥ unlist / soft-delete  
B4 bag qty hostil / cross-seller bag

### CP-C Preço / pago (≥3)
C1 underpay / body `total_eur` hostil (não exacto CDCI)  
C2 coupon/portes hostis com Session open  
C3 **1× Stripe TEST pago** (4242) + ordem/caixa coerente

**Total mínimo = 12.** SKIP técnico → compensar noutro poço.

--------------------------------------------------
## LENTES (≥5/7 com evidência)
--------------------------------------------------
CP1 Session · CP2 claiming · CP3 bag∥ · CP4 stock · CP5 preço · CP6 race · CP7 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · ≥2 races · 1 pago Stripe · P0–P2 = **0** · CONTAGEM coerente  
→ senão `INCONCLUSIVO`. Só então `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CP_MARKETPLACE_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
