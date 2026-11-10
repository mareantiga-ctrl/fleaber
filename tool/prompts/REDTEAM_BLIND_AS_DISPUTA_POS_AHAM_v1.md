# FLEABER — RED TEAM CEGO AS
## Auditor independente · PÓS-FECHO AHAM · DISPUTA / ENVIO / DEVOLUÇÃO PÓS-PAGO · v1

> Fechámos AHAM disputa: stock **não** restaura em `devolvida` com captura Stripe viva; restaura quando chega `stripe_refund_id`; refund-order em `devolvida` permitido (gate terminal antes de shipped); storage provas exige `order_id` no path; `proof_photos` javascript/evil bloqueado; INSERT disputa força `aberta`. Hostile AM PASS.  
> **Poço pós-pago:** envio, disputa, devolução, stock restore, refund no caos.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST (captura real se P0), cegueira, **não corrigir**.

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
Staging: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** (Session **e** pagar 4242 quando o finding exigir captura / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.** · FASE 4: **NÃO INICIAR.**

Actors: anon · buyer · seller · buyer2 · seller2 · conluio.  
`service_role` **só** fixture. Prefixo: `RTAS-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois de pago, consigo (envio/disputa/devolução) dinheiro, stock, ou estado que a UI esconde?**

Não repetir exactos AM/O:
- seller `devolvida` → stock restore sem refund exact AM3
- refund blocked shipped on devolvida exact AM4
- S1 lê provas disputa B1–S2 exact AM7
- proof_photos javascript exact AM7-P2 · INSERT disputa resolvida exact AM3-P3
- seller PATCH disputa resolvida clássico · pago→concluido sem enviado · OCR kick 1442

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta AM/O → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AS (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta-guia |
|---|--------|----------------|
| AS1 | Disputa vs FSM | Abrir/fechar em estados errados |
| AS2 | Enviado ∥ disputa | Ordem cronológica mente |
| AS3 | Devolução / stock | Restore sem refund? 2.º checkout? |
| AS4 | Refund no caos | Parcial, seller pós-release, devolvida gate |
| AS5 | Receção ∩ disputa | Saltos buyer/seller |
| AS6 | Etiqueta / carrier | Enviado sem captura |
| AS7 | Prova disputa | Path/storage alheio, URLs evil |
| AS8 | Composição → Δwallet/stock/Stripe |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 order Stripe TEST **paga**.  
2. Percorrer envio → disputa → devolução (≥2 estados).  
3. Contabilidade: wallets + stock + status.  
4. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_as_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo**, repetir **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AS_DISPUTA_POS_AHAM_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AS1,…]
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

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
