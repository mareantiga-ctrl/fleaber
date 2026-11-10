# FLEABER — RED TEAM CEGO Q
## Auditor independente · PÓS-NOP · REFUTAR FECHO LIVE+DISPUTA · v1

> **Quarta onda** depois de K/L/M/N/O/P.  
> Acabámos de fechar NOP (live spoof, abort devolução, proof/label, escalate, O3/O4).  
> **Poço:** provar que o fecho **não** segura — ou saturar.  
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

Prefixo fixtures: `RTQ-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fixes NOP+O34, ainda consigo dinheiro, stock, autoridade live, ou estado de disputa/devolução que a UI esconde?**

Prioridade: **refutar N-P0/P2 e O-P1/P2/P3** com prova LIVE — não repetir o exploit exacto já documentado sem variante nova.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios K/L/M/N/O/P · “o que já foi corrigido”.

**Podes estudar:** código actual · SQL · RLS · triggers · RPCs · Edge · Flutter (fluxos) · schema LIVE.

Descobre **por ti**. Congela. Só depois (opcional) comparar.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar SQL / migrations / Edge / Flutter / RLS. Não deploy.  
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a parar só em:
dual Session · bag unlist · seguro plain · resolve handle · mux draft ·  
cancel hold · review 5★ · Hub paused · seller PATCH `resolvida` clássico ·  
**spoof seller_id accepted** (sem variante) · **abort pedido_devolucao→enviado** (sem variante) ·  
**proof_url evil** / **label wrap** (sem variante) · **devolvida sem stripe** (sem variante).

Se ≥50% findings = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES Q (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta-guia |
|---|--------|----------------|
| Q1 | Live reserva | Outro campo/JWT além de `seller_id` aceita reserva alheia? |
| Q2 | Egress / publish | Parar ou publicar live alheia por ID leak? |
| Q3 | Devolução pós-O34 | Contornar `order_devolvida_requires_refund` ou `dispute_full_refund_requires_stripe`? |
| Q4 | Race pós-fix | `refund-order` ∥ `devolvida` ∥ `process_partial` ∥ stock restore |
| Q5 | Disputa FSM | Reabrir / saltar estados com JWT buyer ou seller |
| Q6 | Stock ∩ refund | Item relistado com comprador ainda “dono” na UI? |
| Q7 | 2.º actor | Buyer2 / seller2 no mesmo live ou order |
| Q8 | Composição Q*→caixa | Encadear até Δwallet, stock, Stripe net ou autoridade |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 Stripe TEST **pago** + caminho disputa **ou** live reserva.  
2. Contabilidade fechada: buyer wallet · seller wallet · stock · PI · `stripe_refund_id`.  
3. ≥1 race real (`Future.wait`) com verbos **diferentes** dos relatórios N/O.  
4. Flutter ≠ fronteira — REST/RPC/Edge.  
5. Não partir fluxos legítimos: seller `enviado` correcto; refund-order após oferta 100%.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
SESSION ≠ captura ≠ Transfer ≠ net.  
HTTP 200 sem efeito final ≠ P0.  
UI esconde mas API permite **com efeito** = finding.  
P0: dinheiro/stock/autoridade irreversível.  
P1: caminho explorável com prova.  
P2/P3: hygiene sem loot directo.

--------------------------------------------------
CONGELAMENTO · ENTREGA
--------------------------------------------------
Pasta: `tool/redteam_blind_q_<timestamp>/`  
Ficheiro obrigatório: **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_Q_POS_NOP_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [Q1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
