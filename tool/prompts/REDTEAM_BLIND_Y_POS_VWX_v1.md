# FLEABER — RED TEAM CEGO Y
## Auditor independente · PÓS-FECHO VWX · MARKETPLACE / FSM / CHECKOUT · v1

> Acabámos de fechar VWX: `shipped_at`, anti-hop FSM, conjunto exacto no Edge, refund pós-envio bloqueado.  
> **Poço:** provar que estes fechos **não** seguram dinheiro/stock/checkout — ou saturar.  
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

Prefixo fixtures: `RTY-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos VWX, ainda consigo dinheiro Stripe/carteira, pagar menos no conjunto/oferta, ou desfazer envio para refund?**

Prioridade: variantes **novas** — não repetir hop exacto V1, extra-SKU exacto V4, dual Session exacto U.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler: AUDITORIA/HARDENING/PRODUCTION_GATE · relatórios V/W/X/T/U/Q/R/S.

**Podes estudar:** código · SQL · RLS · Edge `create-payment-intent` / `refund-order` · schema LIVE.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a parar só em:
hop `enviado→RP→pago` exact · extra linha mesmo SKU exact ·  
`order_cannot_reopen_pago` directo exact · offer qty=1 exact ·  
bag incompleto exact · Hub qty=0 exact · dual Session exact.

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES Y (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| Y1 | FSM pós-shipped_at | Outro caminho para refund pós-envio? aliases de estado? |
| Y2 | Conjunto / oferta | Pagar menos com bundle, tier, oferta, qty, 2 bundle_id |
| Y3 | Checkout Edge | Session reuse, total_eur, bag parcial, race 2× PI |
| Y4 | Stock / hold | Inflate, ghost hold, devolvida restore |
| Y5 | Disputa×refund | Parcial wallet + Stripe pós-VWX |
| Y6 | Race | Future.wait verbos novos |
| Y7 | 2.º actor | B2/S2 no mesmo order/bag |
| Y8 | Composição → caixa | Encadear até Δwallet / Stripe net / stock |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 Stripe TEST pago + checkout marketplace **ou** disputa.  
2. Contabilidade: wallets · PI · `stripe_refund_id` · `shipped_at` · stock.  
3. ≥1 race real.  
4. REST/RPC/Edge ≠ Flutter.  
5. Não partir: refund antes de enviar; compra single legítima; MB WAY seller `pago`.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_y_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo** do relatório, bloco exacto:

```
AUDITOR: REDTEAM_BLIND_Y_POS_VWX_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [Y1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CONTAGEM`** (obrigatória, números explícitos):

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
```

Secção **`## CHECKLIST`** (28 linhas, responder SIM/NÃO/NÃO COMPROVADO):

1. P0 dinheiro irreversível encontrado  
2. Quantos P0: ___  
3. P1 caminho explorável encontrado  
4. Quantos P1: ___  
5. P2 hygiene encontrado  
6. Quantos P2: ___  
7. P3 baixo risco encontrado  
8. Quantos P3: ___  
9. Buyer manipula preço autoritativo  
10. Buyer manipula qty autoritativa  
11. Seller falsifica pagamento plataforma  
12. JWT cria saldo/fundos  
13. Refund excede captura  
14. Release+refund cria dinheiro líquido  
15. Payout duplica Transfer  
16. Stock=1 duas vendas válidas  
17. Stock=1 duas capturas líquidas permanentes  
18. Bypass capacidade/reserva  
19. Cross-user financeiro  
20. Cross-user dados sensíveis  
21. Buyer assume seller/admin  
22. Seller assume buyer/admin  
23. Reviews forjadas  
24. RPC SECURITY DEFINER perigoso executável  
25. RLS crítico quebrado  
26. Edge confia total do cliente  
27. Regressão funcional (happy path partido)  
28. Saturação atingida  

Cada finding: **ID · severidade · lente · actor · repro · impacto · prova**.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
