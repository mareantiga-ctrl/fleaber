# FLEABER — RED TEAM CEGO DV · DEEP · PÓS-DNDS
## Storage / disputa / label / shipping seal — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DNDS: revoke registry + TTL disputa 15m. Atacar path, actor, janela, selo portes, **e** bypass revoke.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTDV-<timestamp>-` · pasta `tool/redteam_blind_dv_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** order paga + disputa/refund no fio.
3. **≥4 classe_nova** (não só `%252f` / `//`).
4. Oráculo: storage HTTP + RPC proof_ok + BD photos/label + order status.
5. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Proof URL canónica; sem traversal; sem loot alheio.  
> Após DELETE: auth 404; `batata_revoke_private_object` → proof_ok false; signed CDN até exp = residual **documentar** (máx 1 HOLD se ainda 200).  
> Disputa: actor + janela. Shipping: imutável após `cs_`/pago.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
label `%252f` deny · `//` após host · signed CDN 200 pós-DELETE **se** só residual plataforma (1 linha) · dispute window 403 clássico

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### DV-A Storage / path (≥6)
A1 upload `../` outro buyer  
A2 `%2e%2e%2f` / overlong / unicode slash (U+2AFB ou similar **novo**)  
A3 signed URL buyer2 em disputa buyer1  
A4 DELETE + auth GET 404 + **revoke RPC** + proof_ok  
A5 signed GET pós-DELETE (documentar CDN; classe_nova)  
A6 mime JS / polyglot upload

### DV-B Disputa FSM (≥4)
B1 disputa order alheia  
B2 disputa em `enviado` / pós-release  
B3 disputa∥refund race + Δwallet/stock  
B4 PATCH status disputa/order hostil

### DV-C Shipping / label (≥4)
C1 PATCH shipping após `cs_` open  
C2 PATCH shipping após pago  
C3 bag portes mistos (CTT+mão) amount  
C4 label concat / host evil / `@` / `https:/`

### DV-D Caixa (≥2)
D1 disputa feliz proof 201  
D2 refund stock +1 idempotente

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DV1 path · DV2 revoke · DV3 actor · DV4 janela · DV5 shipping · DV6 label · DV7 stock

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DV_STORAGE_POS_DNDS_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
