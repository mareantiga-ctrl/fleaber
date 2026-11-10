# FLEABER — RED TEAM CEGO T
## Auditor independente · PÓS-FECHO Q · REFUTAR LIVE+DISPUTA v2 · v1

> **Quinta onda** — Q encontrou P0/P1; fechámos Q1/Q5/Q6/Q8/Q3 em staging.  
> **Poço:** refutar **estes** fechos — ou saturar neste perímetro.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTT-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fixes Q (live_item∈live, resolvida seller, stock inflate, parcial pós-envio→Stripe, #https://), ainda consigo dinheiro, stock, autoridade live, ou disputa explorável?**

Prioridade: **variantes novas** — não repetir o exploit exacto de Q sem twist.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `PRODUCTION_GATE*`  
relatórios Q/R/S/N/O/P/K–M · “o que já foi corrigido”.

**Podes estudar:** código actual · SQL · RLS · triggers · RPCs · Edge · schema LIVE.

Descobre **por ti**. Congela. Só depois (opcional) comparar.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar SQL / Edge / Flutter / RLS. Não deploy.  
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a parar só em:
dual Session · bag unlist · seguro plain · spoof `seller_id` exact ·  
live_item mismatch exact (sem variante) · abort devolução exact ·  
wrap `/https://` exact · `#https://` exact · devolvida sem stripe exact ·  
parcial 100% exact · review 5★ · Hub paused · cancel hold.

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES T (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta-guia |
|---|--------|----------------|
| T1 | Live reserva v2 | Outro campo além de live_item/live_id? Staff? `facebook_manual`? qty race? |
| T2 | Convert / checkout live | Convert sem PI; PI metadata; cross-pool live↔marketplace |
| T3 | Disputa parcial v2 | Parcial em `pago` vs `entregue`; Stripe partial; buyer2 |
| T4 | Stock v2 | Decrement bypass; bundle; raffle hold; restore devolvida legítima |
| T5 | Resolvida / escalate | Seller bypass Q5; admin forge; buyer reabrir |
| T6 | Race composta | ≥1 `Future.wait` verbos ≠ Q (ex. convert∥expire; partial∥release) |
| T7 | 2.º actor | S2/B2 no mesmo item/order/live |
| T8 | Composição T*→caixa | Encadear até Δwallet, stock, Stripe net ou autoridade |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 Stripe TEST pago + live **ou** disputa.  
2. Contabilidade: buyer wallet · seller wallet · stock · PI · `stripe_refund_id`.  
3. ≥1 race real com verbos diferentes de Q.  
4. REST/RPC/Edge — Flutter ≠ fronteira.  
5. Não partir: reserva legítima same-live; envio carrier correcto; refund-order em `pago`.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
SESSION ≠ captura ≠ Transfer ≠ net.  
HTTP 200 sem efeito final ≠ P0.  
UI esconde mas API permite **com efeito** = finding.

--------------------------------------------------
CONGELAMENTO · ENTREGA
--------------------------------------------------
Pasta: `tool/redteam_blind_t_<timestamp>/`  
Ficheiro obrigatório: **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_T_POS_Q_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [T1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
