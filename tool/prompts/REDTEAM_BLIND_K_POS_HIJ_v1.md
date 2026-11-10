# FLEABER — RED TEAM CEGO K
## Auditor independente · PÓS-FECHO HIJ · REPROVA DINHEIRO + CHAT · v1

> **Não** é Indep/F/G/H genérico.  
> Acabámos de fechar P0 I (levantamento + `devolvida` mint) e P1 J (plain→JSON).  
> A tua missão: **refutar o fecho** — ou declarar saturado neste poço.  
> Mesmas regras duras: staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente (Session **e** pagar 4242 quando o finding exigir captura / Transfer / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTK-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fixes HIJ, ainda consigo: (1) mintar carteira / estorno fantasma após levantamento, ou (2) forjar recibo de sistema no chat?**

Prioridade: **prova LIVE com Δwallet e Stripe TEST**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios H/I/J/G/F · “o que já foi corrigido”.

**Podes estudar:** código actual · SQL · RLS · Edge · schema LIVE · comportamento LIVE.

Descobre **por ti**. Congela. Só depois (opcional) comparar.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar SQL / Edge / Flutter / RLS. Não fazer deploy.  
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a “redescobrir” e parar em:
dual Session · bag unlist · offer morto · pairing ended · Hub paused · invite enum ·  
cancel hold · review 5★ release · tip seller mismatch · helper escalate (H).

Se ≥50% findings = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES K (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| K1 | Payout total → `devolvida` | Buyer wallet sobe sem `stripe_refund_id`? |
| K2 | Clawback saldo 0 | Estorno no livro sem Δbalance? |
| K3 | `refund-order` Stripe após release | Fluxo legítimo ainda funciona? (anti-regressão) |
| K4 | Chat plain→JSON | kinds servidor / `order_paid` / `seguro` unpaid |
| K5 | Chat JSON já gravado | UPDATE ainda imutável? |
| K6 | Off-platform / mão | `devolvida` wallet OK só quando faz sentido? |
| K7 | Composição K*→caixa | Encadear até Δwallet ou Stripe net |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 Stripe TEST **pago** + caminho até release e/ou payout (ou drain fixture).  
2. Contabilidade fechada: buyer wallet · seller wallet · PI · `stripe_refund_id`.  
3. ≥1 tentativa plain→JSON + ≥1 INSERT `seguro_fleaber_paid` em hold não pago.  
4. Flutter ≠ fronteira.  
5. Não partir: mão→`concluido`; seller `enviado`; cancel `reserva_pendente`.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
SESSION ≠ captura ≠ Transfer ≠ net.  
HTTP 200 sem efeito ≠ P0.  
P0: dinheiro/stock irreversível. P1: caminho explorável com prova. P2/P3: hygiene.

--------------------------------------------------
CONGELAMENTO · ENTREGA
--------------------------------------------------
Pasta: `tool/redteam_blind_k_<timestamp>/`  
Ficheiro obrigatório: **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_K_POS_HIJ_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [K1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Por finding: ID · lente · actor · passos · esperado vs obtido · prova (IDs, montantes) · severidade.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
