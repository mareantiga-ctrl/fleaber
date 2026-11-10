# FLEABER — RED TEAM CEGO AA
## Auditor independente · PÓS-FECHO VWX · LIVE MANUAL / STAFF · v1

> Acabámos de fechar X+VWX live: convert exige order paga (todos sources), helper não infla qty, Hub live qty>0.  
> **Poço:** provar que Facebook/manual/staff ainda consome stock sem dinheiro ou sabota live alheia — ou saturar.  
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

Prefixo fixtures: `RTAA-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos X+VWX live, ainda consigo convert/mark_sold sem PI, inflar qty, ou sabotar live de outro?**

Prioridade: variantes **novas** — não repetir fb convert exact X1, helper inflate exact X2.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios X/V/T/Q/N.

**Podes estudar:** RPC live · RLS staff · Edge mux/livekit (sem player UI).

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
fb convert sem PI exact · helper qty 1→40 exact · spoof seller_id exact ·  
live_item mismatch exact · stop_egress foreign exact.

Se ≥50% → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AA (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AA1 | facebook_manual | Convert sem PI — outro caminho? mark_sold? pending? |
| AA2 | Staff helper | Perms; qty; convert; loja alheia |
| AA3 | Qty / sold | Inflate dono; race convert; live_only |
| AA4 | Cross-live / cross-seller | Item entre lives; sabotage |
| AA5 | Mux / publish | Token alheio; draft |
| AA6 | Rifa / share | Se aparecer no caminho |
| AA7 | 2.º seller | PATCH/accept foreign |
| AA8 | Composição → caixa | Convert → order fantasma → Δwallet |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 live activa + reserva `facebook_manual` **e** `fleaber_live`.  
2. ≥1 helper se existir; senão SKIP documentado.  
3. Contabilidade qty / status / orders / wallets.  
4. Não partir: convert fleaber_live **com** order paga; accept legítimo.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_aa_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_AA_LIVE_POS_X_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AA1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**`## CONTAGEM`** (obrigatória):

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
```

**`## CHECKLIST`** (28 linhas — igual Y; preencher todos).

P0 live = dinheiro mint / roubar live alheia com efeito caixa.  
P1 = stock/capacidade sem PI explorável.  
P2/P3 = buyer_id forjado, mark_sold ops, mux draft dono.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
