# FLEABER — RED TEAM CEGO AR
## Auditor independente · PÓS-FECHO AHAM · PAYOUT / WALLET / REFUND · v1

> Fechámos AHAM payout/FSM: cancel pós-pago → **403** (não 200 silencioso); refund gate `devolvida` **antes** de `shipped_at`; stock em `devolvida` só se off-platform ou já `stripe_refund_id`; restore stock quando refund chega. AL hostile PASS.  
> **Poço saída de dinheiro:** payout, Transfer, refund, release, clawback — ainda sai 2× ou mint?  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST (pagar 4242 se P0), cegueira, **não corrigir**.

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
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST.  
Produção proibida · Fase 4 não.  
Prefixo: `RTAR-<timestamp>-`.  
`service_role` só fixture / observação.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Dinheiro na carteira/Connect — consigo tirar 2×, para conta errada, ou refund/release que minta?**

Não repetir exactos AL/I:
- cancel silent 200 exact AL5-cancel-silent-200
- dual Session · payout idempotency clássico · review 5★ release · mint pós-payout

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta AL/I → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AR (obrigatório ≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| AR1 | Payout JWT/Edge hostil · replay idempotency |
| AR2 | Connect return hijack |
| AR3 | Release + refund + clawback = líquido |
| AR4 | Transfer duplicado / webhook replay |
| AR5 | Seller refund após release · parcial > captura · devolvida gate |
| AR6 | Buyer força refund alheio · cancel pós-pago |
| AR7 | Composição até Δwallet / Stripe net |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 fluxo Stripe TEST **pago** + release ou refund.  
2. Contabilidade: buyer wallet · seller wallet · Stripe.  
3. Tentar JWT em RPCs de payout / Transfer.  
4. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_ar_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** no topo.

```
AUDITOR: REDTEAM_BLIND_AR_PAYOUT_POS_AHAM_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AR1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas):

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
