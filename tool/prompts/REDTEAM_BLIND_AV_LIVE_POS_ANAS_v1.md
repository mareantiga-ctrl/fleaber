# FLEABER — RED TEAM CEGO AV
## Auditor independente · PÓS-FECHO ANAS · LIVE MANUAL / STAFF · v1

> Fechámos ANAS live: `batata_live_purchase_broadcast` exige **order paga** do item; INSERT reserva em live **ended** → `live_ended`. AHAM (mark_sold foreign, INSERT sold, Hub GRANT) mantém-se. Hostile ANAS + AJ/AK PASS.  
> **Poço:** convert/mark_sold sem PI, prova social falsa, fila fantasma — ou saturar.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST se preciso, cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

Ver também `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: N
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P3` ou `PASS_CEGO_SATURADO` se 8/8 lentes saturadas
- P0–P3 fechados (TOTAL = 0) → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST só se finding exigir.  
PRODUÇÃO: **PROIBIDO TOCAR.** · FASE 4: **NÃO INICIAR.**  
Actors: seller · helper/staff · buyer · seller2.  
`service_role` **só** fixture. Prefixo: `RTAV-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois ANAS live, ainda anuncio «comprou» sem pagar, convert/mark_sold sem PI, ou sabotar live/catálogo alheio?**

Não repetir exactos AP/AJ/AG/AD:
- purchase_broadcast sem PI exact AP-P2-01 (agora bloqueado — testar INSERT `live_messages` system directo, outro RPC, staff path)
- pending ended exact AP-P3-01 (agora INSERT bloqueado — testar UPDATE pending, reabrir+accept race)
- mark_sold foreign checkout exact AJ4-02 · INSERT sold AJ4-03 · convert sem PI AD1

**Variantes novas:** broadcast com order **cancelada** mas PI vivo; order de **outro** live_item; helper `can_manage_chat` only; race accept após ended **micro** janela.

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Não ler AP/AJ/AG/AD/ANAS antes de congelar. ≥50% exactos → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AV (obrigatório 8/8)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AV1 | Convert bypass | Outro caminho `converted` sem order paga? |
| AV2 | Staff/helper | Escalate, view-only, mark_sold auth |
| AV3 | Stock/Hub/REST | Esgotado/ended visível? pending paused? |
| AV4 | mark_sold / hitch | Deslistar alheio ou sem PI? |
| AV5 | live_id / qty / cross-seller | |
| AV6 | Race accept/convert/broadcast | |
| AV7 | Sabotar live alheia, Mux | |
| AV8 | Caixa — Δ wallet / order fantasma | |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_av_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** + **TOTAL** no topo.

```
AUDITOR: REDTEAM_BLIND_AV_LIVE_POS_ANAS_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AV1, AV2, AV3, AV4, AV5, AV6, AV7, AV8]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas — igual AT).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
