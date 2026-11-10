# FLEABER — RED TEAM CEGO EQ · DEEP LONGO · POS_OPEN_GATE
## Maratona disputa / storage / portes / label / revoke — **quota ≥24**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Ciclo longo: pago → envio → disputa → proof → revoke → reply → refund paths.  
> Tempo esperado: **alto**.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEQ-<timestamp>-` · pasta `tool/redteam_blind_eq_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**24**.
2. **≥2** orders pagas no fio (disputa feliz + race).
3. **≥6 classe_nova** path/actor/janela.
4. Oráculo: storage HTTP + `proof_ok` + BD photos/label + order status + revoke table.
5. JWT INSERT/SELECT revoke = 403. Loot cross-user = P1+.
6. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Proof canónica; sem traversal; sem loot. Revoke sticky.  
> Disputa: actor + janela. Portes/label imutáveis pós-`cs_`/pago.  
> Race disputa∥refund∥release sem mint.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
label `%252f` · `//` · revoke 403 clássico (1) · janela enviado 403 (1)

--------------------------------------------------
## MATRIZ (≥24)
--------------------------------------------------

### EQ-A Storage / path (≥8)
A1 upload `../` buyer2  
A2 `%2e%2e%2f` / overlong / unicode slash **novo**  
A3 `..\` Windows / null byte  
A4 mime JS/HTML/SVG  
A5 signed URL buyer2 em disputa buyer1  
A6 MOVE dest prefixo alheio  
A7 GraphQL revoke collection  
A8 RPC revoke path `../` (objecto alheio intacto)

### EQ-B Revoke / proof_ok (≥5)
B1 DELETE + revoke + proof_ok false + JWT INSERT/SELECT 403  
B2 signed GET pós-DELETE  
B3 re-upload mesmo path → proof_ok ainda false  
B4 proof URL forjada / revogada / query token trick  
B5 revoke mid-disputa + reply UI deny

### EQ-C Disputa FSM (≥5)
C1 disputa order alheia  
C2 janela `pago` / `enviado` / pós-release  
C3 disputa∥refund  
C4 disputa∥release (clawback / 1 efeito)  
C5 happy disputa 201 + PNG signed (pago 4242)

### EQ-D Portes / label (≥4)
D1 PATCH portes após `cs_` open  
D2 PATCH portes após pago  
D3 label traversal / oid forjado / `%252f`  
D4 seller2 lê label/disputa buyer1

### EQ-E Caixa / regressão (≥2)
E1 2.º pago 4242 + disputa feliz  
E2 stock Δ nas races C3/C4 = 0 mint

**Total ≥24.**

--------------------------------------------------
## LENTES
--------------------------------------------------
EQ1 path · EQ2 revoke · EQ3 proof · EQ4 disputa · EQ5 label · EQ6 actor · EQ7 race · EQ8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥24 · ≥6 classe_nova · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EQ_DISPUTE_SHIP_MARATHON_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.** Demorado de propósito.
