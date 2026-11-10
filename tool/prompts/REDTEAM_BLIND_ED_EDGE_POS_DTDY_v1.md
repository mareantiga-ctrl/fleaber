# FLEABER — RED TEAM CEGO ED · DEEP · PÓS-DTDY
## Edge settle / tip / refund / webhook / CORS — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DX saturado uma vez — **não** só buyer refund 403. Atacar settle, tip, webhook forge, CORS, amount metadata, races novas.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTED-<timestamp>-` · pasta `tool/redteam_blind_ed_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** operação dinheiro TEST real (pago / refund / tip Session / transfer).
3. **≥3 races** Edge (settle∥settle, tip∥unpublish, refund∥release).
4. **≥4 classe_nova**.
5. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Settle/webhook **não** confia amount/session do cliente.  
> Tip: amount/`tip_id`/live_id autoridade servidor.  
> Refund idempotente; CORS não reflecte origins hostis.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
buyer refund 403 · tip seller≠owner clássico · Coptic / charset · settle unpaid 400 clássico (1 linha)

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### ED-A Settle / Session (≥5)
A1 settle unpaid / session inexistente  
A2 settle session_id **alheio**  
A3 metadata amount hostil vs servidor  
A4 reuse Session após expire + settle  
A5 GET/POST settle 2× paralelo (idempotency)

### ED-B Tip (≥4)
B1 tip amount / tip_id / live_id hostil  
B2 tip∥end_live / unpublish  
B3 tip seller≠owner (1 residual máx)  
B4 tip unpaid → wallet 0 + tip∥CPI bag

### ED-C Webhook / CORS / refund (≥4)
C1 webhook forge signature / replay body  
C2 CORS `Origin` evil / chrome-extension / null  
C3 buyer refund 403 (1 residual) + seller refund idempotente 2×  
C4 refund∥release race

### ED-D Caixa (≥3)
D1 **pago 4242** + settle coerente order/wallet  
D2 tip pago TEST + Δwallet  
D3 amount_total Session ≠ body cliente (servidor ganha)

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
ED1 settle · ED2 tip · ED3 webhook · ED4 CORS · ED5 refund · ED6 race · ED7 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · ≥3 races · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_ED_EDGE_POS_DTDY_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
