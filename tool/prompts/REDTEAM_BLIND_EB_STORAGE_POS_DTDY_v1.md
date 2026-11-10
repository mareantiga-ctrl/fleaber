# FLEABER — RED TEAM CEGO EB · DEEP · PÓS-DTDY
## Storage / disputa / label / revoke registry — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DTDY: sem GRANT JWT em `batata_private_object_revoked`; `batata_dispute_proof_url_ok` lê registry. Atacar bypass revoke + path + FSM.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEB-<timestamp>-` · pasta `tool/redteam_blind_eb_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** order paga + disputa/refund no fio.
3. **≥4 classe_nova**.
4. Oráculo: storage HTTP + RPC proof_ok + BD photos/label + order status + **SELECT/INSERT revoke table**.
5. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> JWT **não** INSERT/SELECT directo no registry revoke (DV P1).  
> Após revoke: proof_ok false; auth GET 404.  
> Disputa actor+janela; shipping imutável pós-`cs_`/pago.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
label `%252f` deny · `//` após host · revoke INSERT deny + proof_ok false (1 linha reteste) · dispute window 403 clássico · signed CDN residual (1 linha)

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### EB-A Storage / path / revoke (≥6)
A1 upload `../` outro buyer  
A2 `%2e%2e%2f` / overlong / unicode slash **novo**  
A3 signed URL buyer2 em disputa buyer1  
A4 DELETE + revoke RPC + proof_ok false (reteste)  
A5 JWT **INSERT/SELECT** `batata_private_object_revoked` (deve deny — reteste DV)  
A6 mime JS / polyglot + path com null byte / `..\` Windows-style

### EB-B Disputa FSM (≥4)
B1 disputa order alheia  
B2 disputa em `enviado` / pós-release  
B3 disputa∥refund race + Δwallet/stock  
B4 proof URL forjada (path alheio / object revogado / URL antiga)

### EB-C Shipping / label (≥3)
C1 PATCH portes após `cs_` open / pago  
C2 label path traversal + forge order_id  
C3 seller2 lê label buyer1

### EB-D Caixa (≥3)
D1 **pago 4242** + open disputa + proof upload OK actor  
D2 revoke mid-disputa → proof_ok  
D3 re-upload mesmo path após revoke

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
EB1 path · EB2 revoke · EB3 proof_ok · EB4 disputa · EB5 label · EB6 actor · EB7 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EB_STORAGE_POS_DTDY_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
