# FLEABER — RED TEAM CEGO AD
## Auditor independente · PÓS-FECHO YZAA · LIVE MANUAL / STAFF · v1

> Fechámos AA (ronda 20260901T1715): PATCH `converted` exige order paga, Hub filtra `available_qty>0`, `mark_sold` não deslista marketplace sem PI, `live_id` imutável com reservas, `processed_by_user_id` gravado.  
> **Poço:** refutar — provar que Facebook/manual/staff ainda consome stock sem dinheiro — ou saturar.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST se preciso, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** só se finding exigir.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: seller · helper/staff · buyer · seller2.  
`service_role` **só** fixture.

Prefixo fixtures: `RTAD-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos YZAA live, ainda consigo PATCH converted sem PI, esgotar stock via Hub fantasma, ou mark_sold sem pagamento?**

Prioridade: variantes **novas** — não repetir PATCH converted exact AA1, helper converted exact AA2, qty+converted exact AA3, hub listing exact AA3-hub.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios AA/Y/Z/X/V.

**Podes estudar:** RPC live · RLS staff · guards reserva · view Hub.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
PATCH converted sem PI exact · helper PATCH converted exact · qty+converted exact ·  
hub converted listed exact · mark_sold mkt exact · live_id move exact.

Se ≥50% → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AD (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AD1 | Convert bypass | Outro caminho para `converted` sem order paga? |
| AD2 | Staff/helper | Permissões finas ainda furam? |
| AD3 | Stock / Hub | Item esgotado ainda visível? |
| AD4 | mark_sold | Deslistar marketplace sem PI? |
| AD5 | live_id / qty | Mover item ou inflar qty? |
| AD6 | Race | Dois PATCH converted simultâneos? |
| AD7 | Cross-seller | Sabotar live alheia? |
| AD8 | Caixa | Δ wallet / order fantasma? |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ad_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_AD_POS_YZAA_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AD1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CONTAGEM`** (obrigatória):

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
```

Secção **`## CHECKLIST`** (28 linhas — copiar modelo AA).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
