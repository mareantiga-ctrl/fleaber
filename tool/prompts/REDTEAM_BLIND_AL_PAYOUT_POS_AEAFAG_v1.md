# FLEABER — RED TEAM CEGO AL
## Auditor independente · PÓS-FECHO AEAFAG · PAYOUT / WALLET / REFUND · v1

> **Poço saída de dinheiro:** Connect, Transfer, payout, wallet debit, clawback, refund residual. Residuais pré-Fase4 fechados (finalize refund RPC, idempotency payout) — provar que **ainda** sai dinheiro a mais ou duplicado.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P2` ou `PASS_CEGO_SATURADO` se saturado
- P0–P3 fechados → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Session + pagar 4242 quando preciso).  
Produção proibida · Fase 4 não.  
Prefixo: `RTAL-<timestamp>-`.  
`service_role` só fixture / observação.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **O dinheiro que já está (ou parece estar) na carteira / Connect — consigo tirá-lo duas vezes, para a conta errada, ou sem direito?**

Não re-provar: dual Session (AH) · offer amount · tip mint · invite enum.

Prioridade: **Δwallet líquido · Transfer · payout · clawback · refund após release**.

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Não ler HARDENING como roteiro.  
≥50% = dual Session · bag unlist · cancel hold · review 5★ release · payout idempotency clássico → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AL (obrigatório ≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| AL1 | Payout / `wallet_payout_debit` JWT ou Edge hostil |
| AL2 | Connect return_url / onboarding hijack → conta errada |
| AL3 | Release + refund + clawback = dinheiro líquido |
| AL4 | Transfer duplicado / replay webhook payout |
| AL5 | Seller refund após já ter release |
| AL6 | Buyer força reembolso alheio / parcial > captura |
| AL7 | Composição AL* até Stripe net ou wallet Δ |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 fluxo Stripe TEST **pago** + caminho até release ou refund.  
2. Contabilidade fechada: buyer wallet · seller wallet · Stripe.  
3. Tentar JWT em RPCs de payout / Transfer.  
4. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_al_<timestamp>/FROZEN_REPORT.md`

No **topo**, repetir **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AL_PAYOUT_POS_AEAFAG_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AL1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas, responder SIM/NÃO/NÃO COMPROVADO):

1. P0 dinheiro irreversível encontrado — …
2. Quantos P0: …
3. P1 caminho explorável encontrado — …
4. Quantos P1: …
5. P2 hygiene encontrado — …
6. Quantos P2: …
7. P3 baixo risco encontrado — …
8. Quantos P3: …
9. Buyer manipula preço autoritativo — …
10. Buyer manipula qty autoritativa — …
11. Seller falsifica pagamento plataforma — …
12. JWT cria saldo/fundos — …
13. Refund excede captura — …
14. Release+refund cria dinheiro líquido — …
15. Payout duplica Transfer — …
16. Stock=1 duas vendas válidas — …
17. Stock=1 duas capturas líquidas permanentes — …
18. Bypass capacidade/reserva — …
19. Cross-user financeiro — …
20. Cross-user dados sensíveis — …
21. Buyer assume seller/admin — …
22. Seller assume buyer/admin — …
23. Reviews forjadas — …
24. RPC SECURITY DEFINER perigoso executável — …
25. RLS crítico quebrado — …
26. Edge confia total do cliente — …
27. Regressão funcional (happy path partido) — …
28. Saturação atingida — …

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
