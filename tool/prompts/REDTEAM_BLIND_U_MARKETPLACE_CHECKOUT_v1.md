# FLEABER — RED TEAM CEGO U
## Auditor independente · MARKETPLACE / CHECKOUT / SACO · v1

> **Poço:** compra **fora do directo** — saco, oferta, conjunto, checkout Stripe, MB WAY, stock marketplace.  
> Não re-auditar live bag (Q/T), payout (R), identidade (S).  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** (Session + 4242 quando exigir captura/refund).  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · conluio.  
`service_role` **só** fixture / observação — **nunca** actor do exploit.

Prefixo fixtures: `RTU-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **No marketplace (anúncio, saco, oferta, bundle, checkout), consigo pagar menos, comprar stock inexistente, ou desviar dinheiro/stock?**

Prioridade: **preço servidor · oversell · bag qty · unlist · oferta morta · conjunto · MB WAY mentira · cross-superfície stock**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `PRODUCTION_GATE*`  
relatórios Q/R/S e ondas anteriores.

**Podes estudar:** código · SQL · Edge checkout/settle/refund · RLS · Flutter fluxos compra.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
dual Session clássico · bag unlist exact · preço body Session ·  
oversell última unidade exact (sem variante) · wallet INSERT ·  
cancel hold · review 5★.

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES U (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| U1 | Saco / qty | `bag_update_qty` race; 9999; unlist alheio; cross-seller bag |
| U2 | Oferta / bundle | Aceitar oferta morta; preço bundle ≠ checkout; supersede stock |
| U3 | Checkout Stripe | Quote servidor vs body; portes; desconto; `ensure_checkout_product` |
| U4 | Oversell v2 | Race 2 buyers última unidade; hold∥sold; live+marketplace mesmo SKU |
| U5 | MB WAY / mão | Seller `pago` sem prova; buyer `concluido` cedo; refund inexistente |
| U6 | Cancel / refund | Anular pós-pago; restock duplo; Seguro refund buyer JWT |
| U7 | Cross-superfície | Stock/preço coerente Início ↔ Hub ↔ encomenda ↔ chat |
| U8 | Composição U*→caixa | Encadear até Δwallet, stock, Stripe net |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 checkout Stripe TEST **pago** no marketplace (não só live).  
2. Contabilidade fechada por order: stock · PI · status · wallets.  
3. ≥1 race (`Future.wait`) — ex. checkout∥unlist; 2 buyers∥última unidade.  
4. ≥1 fluxo MB WAY ou mão se aplicável.  
5. Não partir: compra legítima single-item; vendedor envio correcto.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_u_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_U_MARKETPLACE_CHECKOUT_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [U1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
