# FLEABER — RED TEAM CEGO AM
## Auditor independente · PÓS-FECHO AEAFAG · DISPUTA / ENVIO / DEVOLUÇÃO PÓS-PAGO · v1

> **Poço pós-pago** (AEAFAG não cobre): envio, disputa, devolução, stock restore, refund no meio do caos.  
> Não re-auditar checkout (AH) nem cron (L) nem Hub (AK).  
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
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** (Session **e** pagar 4242 quando o finding exigir captura / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: anon · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup.

Prefixo fixtures: `RTAM-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois de pago, consigo (com envio, disputa, devolução ou reembolso no meio) dinheiro, stock, autoridade ou um estado que a UI esconde?**

Prioridade: **FSM pós-pago · disputa ∩ envio · stock restore · refund residual · races enviado∥disputa∥receção**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler: AUDITORIA* · HARDENING* · relatórios K/L/M/O/J/I.

**Podes estudar:** código · SQL · RLS · triggers · RPCs · Edge · Flutter fluxos.

--------------------------------------------------
NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a redescobrir: dual Session · seguro plain · seller PATCH disputa resolvida clássico · pago→concluido carrier sem enviado · OCR kick 1442 · cancel pós-pago.  
≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AM (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta-guia |
|---|--------|----------------|
| AM1 | Disputa vs FSM | Abrir/fechar disputa em pago/enviado/concluido — JWT alheio? |
| AM2 | Enviado ∥ disputa | Seller enviado com disputa; buyer disputa pós-envio |
| AM3 | Devolução / stock | `pedido_devolucao` · restore stock · item volta sem refund / refund duplo |
| AM4 | Refund no caos | Refund a meio envio; parcial; seller após release |
| AM5 | Receção ∩ disputa | Buyer concluido com disputa; seller força receção |
| AM6 | Etiqueta / carrier | Label sem captura; enviado sem portes |
| AM7 | Evidência disputa | Upload/path/storage prova — ler/escrever alheio |
| AM8 | Composição AM*→caixa | Encadear até Δwallet, stock, Stripe net |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 order Stripe TEST **paga** (setup_paid_order ou checkout real).  
2. Percorrer envio → disputa → devolução (pelo menos 2 estados).  
3. Contabilidade: wallets + stock + status order.  
4. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_am_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo**, repetir **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AM_DISPUTA_POS_AEAFAG_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AM1,…]
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

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
