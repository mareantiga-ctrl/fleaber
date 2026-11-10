# FLEABER — RED TEAM CEGO CJ · DEEP v2 · PÓS-FECHO CDCI
## Marketplace / checkout / saco — **quota ≥20 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> CD–CI falhou em profundidade neste poço (só 1 P2). **Agora: matriz obrigatória + TABELA DE PROVAS.**

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL)
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

Prefixo `RTCJ-<timestamp>-` · `tool/redteam_blind_cj_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO (porque a ronda passada foi rasa)
--------------------------------------------------
1. Secção **`## TABELA DE PROVAS`** no FROZEN: **≥20 linhas** (uma por tentativa LIVE).
2. Colunas: `probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD|FAIL|SKIP`.
3. **≥3 races** `Future.wait` distintas (linhas na tabela).
4. **≥1** checkout Stripe TEST **pago** (4242) + contabilidade order.
5. Sem isto → **`INCONCLUSIVO`** (proibido `PASS_CEGO_SATURADO`).
6. Parar após 3 HOLDs → relatório **inválido**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Ainda 2 Sessions pagáveis, total abaixo do contrato, stock fantasma, coupon/portes hostis — **fora** dos exactos CDCI (TTL reclaim clássico, bag∥single)?

--------------------------------------------------
## ANTI-ATROFIA (não contar exactos)
--------------------------------------------------
claiming órfão TTL clássico · bag∥single dual · 3-sacos A∩B∩C · underpay body clássico.  
≥50% só residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (cada item = ≥1 linha na TABELA)
--------------------------------------------------

### CJ-A Claim / Session (≥8 probes)
A1 TTL−10s dual reclaim A∥B  
A2 TTL+1s reclaim  
A3 Session expire Stripe → 2.ª Session mesma order  
A4 crash/timeout mid-claim + retry  
A5 bag 4-line ∥ bag 2-line overlap parcial  
A6 PATCH qty/price com Session open  
A7 settle GET unpaid + orphan PI list  
A8 claim token malformado `claiming:abc` / sem ms / ms futuro

### CJ-B Preço / coupon / portes (≥5)
B1 coupon outro seller / expirado / Unicode  
B2 portes 0 / negativo no body  
B3 bundle `total_eur` hostil  
B4 offer amount freeze encoding novo (não ZWJ residual)  
B5 currency non-EUR / fullwidth digits

### CJ-C Stock / race (≥5)
C1 2 buyers última unidade  
C2 checkout∥unlist  
C3 checkout∥soft-delete  
C4 `is_sold=true` mid-checkout  
C5 bag qty 9999 / cross-seller bag

### CJ-D FSM / pós-pago (≥2)
D1 seller `pago` MB WAY sem prova  
D2 cancel/refund JWT buyer pós-pago

**Total mínimo = 20.** Se um SKIP técnico, compensar com probe extra noutro poço (documentar).

--------------------------------------------------
## LENTES (≥6/8 com evidência na tabela)
--------------------------------------------------
CJ1 preço · CJ2 Session · CJ3 bundle · CJ4 FSM · CJ5 stock · CJ6 race · CJ7 2.º actor · CJ8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥20 · ≥3 races · 1 pago Stripe · poços A–D · lentes ≥6 · CONTAGEM coerente  
→ senão `INCONCLUSIVO`.

```
AUDITOR: REDTEAM_BLIND_CJ_MARKETPLACE_POS_CDCI_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
