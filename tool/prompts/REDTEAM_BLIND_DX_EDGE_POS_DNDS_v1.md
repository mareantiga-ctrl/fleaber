# FLEABER — RED TEAM CEGO DX · DEEP · PÓS-DNDS
## Edge settle / tip / refund / webhook / CORS — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Dinheiro na **Edge**. DL/DR saturaram parcialmente — atacar settle, tip, webhook forge, CORS, amount metadata.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTDX-<timestamp>-` · pasta `tool/redteam_blind_dx_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** operação dinheiro TEST real (pago / refund / tip Session / transfer).
3. **≥3 races** Edge (settle∥settle, tip∥unpublish, refund∥release).
4. **≥4 classe_nova**.
5. Buyer refund seller-only → documentar (HOLD se só 403 clássico).
6. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Settle/webhook **não** confia amount/session do cliente.  
> Tip: amount/`tip_id`/live_id autoridade servidor; unpaid não credita.  
> Refund idempotente; CORS não reflecte `chrome-extension://` / evil origin.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
buyer refund 403 · tip seller≠owner clássico · Coptic / charset

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### DX-A Settle / Session (≥5)
A1 settle unpaid / session inexistente  
A2 settle session_id **alheio** (outra order/buyer)  
A3 metadata amount hostil vs servidor  
A4 reuse Session após expire + settle  
A5 GET settle 2× paralelo (idempotency)

### DX-B Tip (≥4)
B1 tip amount / tip_id / live_id hostil no body  
B2 tip∥end_live / unpublish  
B3 tip seller≠owner (1 residual máx)  
B4 tip Session TEST ou unpaid oracle (Δwallet 0)

### DX-C Refund / webhook / CORS (≥5)
C1 buyer `refund-order` → 403 (HOLD se só isto)  
C2 seller refund 2× idempotente  
C3 refund∥release race  
C4 webhook/`stripe` forge sem assinatura (Edge) — documentar 400/401  
C5 CORS Origin `https://evil.com` / `chrome-extension://abc` (não echo)

### DX-D Caixa (≥2)
D1 **pago ou tip Session** com prova Stripe TEST  
D2 Connect transfer residual (se aplicável) sem double

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DX1 settle · DX2 tip · DX3 refund · DX4 webhook · DX5 CORS · DX6 race · DX7 Δwallet

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · ≥3 races · 1 dinheiro TEST · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DX_EDGE_POS_DNDS_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
