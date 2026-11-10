# FLEABER — RED TEAM CEGO EO · DEEP LONGO · POS_OPEN_GATE
## Maratona dinheiro — settle / webhook / tip / refund / payout / idempotency — **quota ≥28**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Auditoria **longa**: esgotar Edge e caixa. Não repetir só buyer refund 403.  
> Tempo esperado: **alto** (muitos PI, tips, payouts, races).

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM completo + `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.  
`tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTEO-<timestamp>-` · pasta `tool/redteam_blind_eo_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**28** LIVE (pode passar 30–35).
2. **≥5** operações dinheiro TEST reais (pago / refund / tip Session / Transfer).
3. **≥6 races** Edge distintas.
4. **≥8 classe_nova**.
5. Residual clássico ≥40% → `ATROFIA_ABORT`.
6. Mint JWT / double Transfer / settle hostil que credita = finding.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> O servidor manda no dinheiro. Cliente amount/session/tip_id/webhook forge **não** mintam.  
> Idempotency: 2× settle / 2× refund / 2× payout → 1 efeito.  
> Tip unpaid nunca credita; CORS não ecoa origins hostis.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 cada — não contar)
--------------------------------------------------
buyer refund 403 · tip seller≠owner · settle unpaid 402 · Coptic/charset

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥28)
--------------------------------------------------

### EO-A Settle / Session (≥7)
A1 POST settle qs unpaid / metadata hostil  
A2 GET settle session inexistente / whitespace / `pi_` como sid  
A3 settle session **alheia** (outra order/buyer)  
A4 amount body/qs ≠ quote servidor  
A5 GET∥POST settle paralelo  
A6 reuse Session após “cancel” path  
A7 `fase2_e2e_settle` JWT (deve deny service_role)

### EO-B Tip (≥6)
B1 amounts hostis (0, −1, `1e6`, string, tip_id fake, live fake)  
B2 RPC `batata_settle_live_tip_from_stripe` JWT  
B3 tip∥end_live / unpublish  
B4 tip∥CPI bag mesmo buyer  
B5 tip unpaid GET settle Δwallet=0  
B6 tip seller≠owner (1 residual máx)

### EO-C Webhook / CORS / refund (≥7)
C1 webhook sem sig + sig morta + **replay 2×** mesmo body  
C2 CORS Origin `null` / evil / chrome-extension em CPI/tip/refund/webhook  
C3 buyer refund 403 + seller refund **3×** (idempotency)  
C4 refund∥release  
C5 refund amount > captura (se API expuser)  
C6 refund order alheia seller2  
C7 refund após `enviado`/`concluido` (janela)

### EO-D Payout / wallet forge (≥5)
D1 JWT insert txn / PATCH balance / dest Connect  
D2 payout overbalance + dest alheio  
D3 payout∥payout mesma key + keys diferentes  
D4 clawback/credit RPC JWT  
D5 release∥disputa 0ms + 50ms (net≠ crédito+claim)

### EO-E Caixa longa (≥3)
E1 **≥3** pagos 4242 distintos no fio  
E2 tip Session unpaid + 1 tip path documentado  
E3 Transfer count = n esperado (sem double)

**Total mínimo = 28.** Extra probes OK se classe_nova.

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
EO1 settle · EO2 tip · EO3 webhook · EO4 CORS · EO5 refund · EO6 payout · EO7 race · EO8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥28 · ≥8 classe_nova · ≥6 races · ≥5 $$ TEST · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EO_MONEY_MARATHON_POS_OPEN_v1
probes_na_tabela: N · classes_novas: N · races: N · stripe_ops: N
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.** Demorado de propósito.
