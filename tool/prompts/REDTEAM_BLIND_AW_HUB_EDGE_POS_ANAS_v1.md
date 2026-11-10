# FLEABER — RED TEAM CEGO AW
## Auditor independente · PÓS-FECHO ANAS · HUB WEB / EDGE / DEEP LINK · v1

> Fechámos ANAS Hub/Edge: gorjeta + Mux usam **`batata_live_is_broadcasting()`** (scheduled≠ao vivo); anon `batata_live_item_stock` **gated** (gravado/hidden → `live_item_not_found`, Hub GRANT mantido); REST buyer exige `quantity>0` como Hub. Hostile ANAS + AK PASS.  
> **Poço:** web/Edge ainda vaza stock, preço, playback prematuro ou settle alheio?  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

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
- P0–P2 fechados + só P3 → `FAIL_P3` ou `PASS_CEGO_SATURADO` se 7/7 lentes saturadas
- P0–P3 fechados (TOTAL = 0) → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não.  
Prefixo: `RTAW-<timestamp>-`.  
Anon + JWT + origins hostis (`web_return_origin` / CORS).  
`service_role` só fixture.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Pela web / Edge / link, consigo dinheiro, stock, playback ou dados que a vitrine esconde?**

Não re-auditar checkout JWT (AT) nem chat (AU).

Não repetir exactos AQ/AK:
- tip scheduled+is_active exact AQ-P2-01 (agora 400 — testar `paused`, `draft`, `ao_vivo` typo, `is_active` flip race)
- mux scheduled HLS/VOD exact AQ-P2-02 (agora broadcasting gate — testar cache VOD ended vs paused)
- anon stock ended exact AQ-P3-01 (agora not_found — testar UUID de item **no ar** via leak alternativo, GraphQL, total_qty RPC)
- hitch null qty REST exact AQ-P3-02 (agora quantity>0 — testar price=0, status typo, discovery vs player)
- Hub 401 GRANT exact AK1 · tip ended AK4 · REST hitch ended AK1

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta AQ/AK → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AW (obrigatório 7/7)
--------------------------------------------------
| # | Lente |
|---|--------|
| AW1 | Hub views / FOMO / handle — leak além do publicado |
| AW2 | `web_return_origin` / CORS / Connect return evil |
| AW3 | Settle GET `session_id` alheio/forjado |
| AW4 | Edge body spoof (`buyer_id`, `amount`, `tip_id`, `order_id`) + tip/mux gate |
| AW5 | Mux/LiveKit create/complete cross-user |
| AW6 | Storage público vs privado |
| AW7 | Composição → Session/captura / stock oracle |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Anon Hub exercitado (views + FOMO + RPC stock).  
2. ≥2 Edges com body/origin hostil.  
3. ≥1 settle/checkout com id alheio.  
4. Session criada ≠ captura.  
5. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_aw_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** + **TOTAL** no topo.

```
AUDITOR: REDTEAM_BLIND_AW_HUB_EDGE_POS_ANAS_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AW1, AW2, AW3, AW4, AW5, AW6, AW7]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas — igual AT).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
