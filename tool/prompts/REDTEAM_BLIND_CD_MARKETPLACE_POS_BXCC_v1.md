# FLEABER — RED TEAM CEGO CD · DEEP
## Auditor independente · PÓS-FECHO BXCC · MARKETPLACE / CHECKOUT / SACO · v1-deep

> Fechámos BXCC: bag∥single partilham `batata_bag_checkout_claim`. Hostile PASS.  
> **Este prompt é DENSO:** uma corrida tem de esgotar vários poços e variantes — não um único “novo” e parar.  
> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 **não** · **NÃO CORRIGIR**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0? SIM|NÃO  2. Quantos P0: N
3. P1? SIM|NÃO  4. Quantos P1: N
5. P2? SIM|NÃO  6. Quantos P2: N
7. P3? SIM|NÃO  8. Quantos P3: N
```
**Sem TOTAL numérico → INVÁLIDO.** Cada finding aberto = ID `P0-1` / `P1-1`…; soma = quantos.

Prefixo fixtures: `RTCD-<timestamp>-` · pasta: `tool/redteam_blind_cd_<timestamp>/`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> No marketplace (anúncio, saco, oferta, conjunto, checkout Stripe/MB WAY), ainda consigo **pagar menos**, **duas Sessions pagáveis**, **stock inexistente**, ou **desviar dinheiro/stock** — com variantes que **não** sejam o exacto bag∥single já fechado?

Prioridade: preço servidor · claim/lock · oversell · oferta/bundle · currency/encoding no amount · settle órfão · cross-superfície.

--------------------------------------------------
## CEGUEIRA · NÃO CORRIGIR · ACTORS
--------------------------------------------------
**NÃO ler** antes do freeze: `AUDITORIA*` · `HARDENING*` · `PRODUCTION_GATE*` · FROZEN de BX–CC / BRBW.  
**Podes estudar:** código · SQL · Edge checkout/settle · RLS · Flutter fluxos compra.

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · conluio.  
`service_role` **só** fixture/observação — **nunca** actor do exploit.

Finding = **PROVAR → DOCUMENTAR → CONTINUAR**. Sem patch.

--------------------------------------------------
## ANTI-ATROFIA (não contar / não parar só nisto)
--------------------------------------------------
Exactos **já fechados** (residual no máximo; ≥50% = `ATROFIA_ABORT`):
- bag∥single dual open Session (mesmo claim)
- 3 sacos A∩B∩C / AB∥AC dual clássico
- underpay body ignorado no single clássico
- preço UI ≠ Stripe se servidor já corrige e Stripe bate contrato

**Conta** se: variante nova (4+ lines, crash mid-claim, currency ZWJ, offer freeze, settle orphan list, bag+marketplace live mesmo SKU, etc.) com prova LIVE.

--------------------------------------------------
## POÇOS OBRIGATÓRIOS (≥4 — todos tentados com estado final)
--------------------------------------------------

### POÇO CD-A — LOCK / SESSIONS (matriz)
Não pares no 1.º fail. Tenta **na mesma corrida**:
1. bag∥single mesma order (regressão — só residual se fail)
2. **4+ lines** no saco → 1 claim / N Sessions?
3. **crash mid-claim** (matar request / timeout / 2.º RPC retry) → 2 `cs_` open?
4. bag A + bag B **parcial overlap** SKUs (não o triângulo clássico)
5. metadata drift pós-claim (alterar line qty/price via RPC/PostgREST enquanto Session open)
6. list Stripe Sessions orphan (order sem PI / PI sem order / 2 PI 1 order)

### POÇO CD-B — PREÇO / CURRENCY / ENCODING
1. amount / currency com ZWJ, bidi, fullwidth digits, NBSP no body Edge
2. portes / desconto / bundle line vs Session `amount_total`
3. offer aceite → freeze Unicode no amount → checkout abaixo
4. `ensure_checkout_product` / quote servidor vs body hostil

### POÇO CD-C — STOCK / OVERSELL / UNLIST
1. Race 2 buyers última unidade (`Future.wait`)
2. checkout∥unlist / soft-delete / `list_on_marketplace=false`
3. hold∥sold; live+marketplace **mesmo SKU** (se fixture permitir)
4. `bag_update_qty` 9999 / qty alheia / cross-seller bag

### POÇO CD-D — FSM / MB WAY / PÓS-PAGO
1. seller marca `pago` sem prova; buyer `concluido` cedo
2. cancel pós-pago; restock duplo; refund buyer JWT Seguro
3. settle return URL vs webhook ordem invertida

### POÇO CD-E — COMPOSIÇÃO ATÉ CAIXA (obrigatório ≥1)
Encadear até Δwallet (ou prova de ausência) + stock + Stripe net numa order. Sem isto → não `PASS_CEGO_SATURADO`.

--------------------------------------------------
## LENTES CD (cobrir ≥6/8 com evidência)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| CD1 | Preço | Contrato servidor vs body; encoding amount |
| CD2 | Session/saco | Claim; dual `cs_`; orphan list |
| CD3 | Bundle/oferta | Aceitar morta; supersede; freeze |
| CD4 | FSM | Saltos pago/enviado/concluido |
| CD5 | Stock | Oversell; unlist; qty |
| CD6 | Race | ≥2 `Future.wait` distintos |
| CD7 | 2.º actor | Buyer fresco / seller mentiroso |
| CD8 | Caixa | Δwallet · stock · Stripe |

--------------------------------------------------
## TÁCTICAS MÍNIMAS (senão INCONCLUSIVO)
--------------------------------------------------
1. ≥1 checkout Stripe TEST **pago** (4242) no marketplace.  
2. ≥2 races distintas (não a mesma duas vezes).  
3. ≥1 tentativa encoding/currency no amount ou metadata.  
4. Contabilidade fechada por order: stock · PI/Session · status · wallets.  
5. Não partir compra legítima single-item / envio correcto do vendedor.

--------------------------------------------------
## SATURAÇÃO → `PASS_CEGO_SATURADO`
--------------------------------------------------
Só se: poços A–E tentados · lentes ≥6 · tácticas 1–4 · CONTAGEM P0–P3 = 0 (ou só P3 residual documentado) · anti-atrofia OK.  
Senão: `FAIL_P*` ou `INCONCLUSIVO`.

--------------------------------------------------
## CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_CD_MARKETPLACE_POS_BXCC_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CD1,…]
pocos_tentados: [CD-A,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Checklist invariantes A–L + checklist 28 se aplicável. **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
