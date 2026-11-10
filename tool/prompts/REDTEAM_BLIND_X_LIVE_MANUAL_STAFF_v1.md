# FLEABER — RED TEAM CEGO X
## Auditor independente · LIVE FACEBOOK / MANUAL / STAFF · v1

> **Poço:** reservas **fora** do saco in-app clássico — `facebook_manual`, helper/staff, convert sem Stripe quando o produto permite.  
> Não re-auditar mismatch `live_item∈live` exact (Q/T) nem payout (R).  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST se preciso, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** só se o finding exigir.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: seller · helper/staff · buyer · seller2.  
`service_role` **só** fixture.

Prefixo fixtures: `RTX-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **No directo (Facebook/manual/staff), consigo marcar vendido sem dinheiro, roubar stock, ou sabotar a live de outro?**

Prioridade: **`facebook_manual` convert · staff perms · qty live · cross-seller helper**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING nem relatórios N/Q/T.

**Podes estudar:** SQL live · RPCs · Edge livekit/mux (sem mexer player UI).

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
spoof `seller_id` exact · `live_item_live_mismatch` exact ·  
`convert_requires_paid_order` exact em `fleaber_live` · stop_egress foreign exact.

Se ≥50% → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES X (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| X1 | facebook_manual | Accept/convert sem PI; qty; buyer_id |
| X2 | Staff helper | Perms alargadas; convert; reserva loja alheia |
| X3 | Qty / sold | Inflate mid-live; sold sem convert; race |
| X4 | Cross-live | Item/product entre lives do mesmo seller |
| X5 | Mux / publish | Token alheio; draft (variante nova) |
| X6 | Rifa / share | Só se aparecer no caminho live |
| X7 | 2.º seller | Sabotage stock / accept |
| X8 | Composição → caixa | Convert → order fantasma → dinheiro |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 live activa (fixture) + reserva `facebook_manual` **e** `fleaber_live`.  
2. ≥1 staff/helper se existir conta; senão documentar SKIP.  
3. Contabilidade item qty / status / order se criada.  
4. REST/RPC/Edge.  
5. Não partir: convert `fleaber_live` **com** order paga; accept same-live legítimo.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_x_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_X_LIVE_MANUAL_STAFF_v1
production_touched: false
fase4: false
VEREDICTO: FAIL_P0 | FAIL_P1 | … | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
