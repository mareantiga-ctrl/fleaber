# FLEABER — RED TEAM CEGO DI · DEEP · PÓS-DBDG
## Ofertas / bundles / chat dinheiro / inbox — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Chat notes já saturado (CW/DC). Foco: **propostas, conjuntos, composição dinheiro no chat**.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco do FROZEN (INVÁLIDO sem números N)
--------------------------------------------------
**Obrigatório:** `quantos` = 0,1,2… · TOTAL = P0+P1+P2+P3 · ver `REDTEAM_CONTAGEM_OBRIGATORIO.md`

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0 dinheiro irreversível? SIM|NÃO
2. Quantos P0: N
3. P1 caminho explorável? SIM|NÃO
4. Quantos P1: N
5. P2 hygiene? SIM|NÃO
6. Quantos P2: N
7. P3 baixo risco? SIM|NÃO
8. Quantos P3: N
```

Prefixo `RTDI-<timestamp>-` · pasta `tool/redteam_blind_di_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**14** linhas.
2. Colunas: `probe_id | superfície | payload | HTTP/RPC | BD/ledger | HOLD|FAIL|SKIP`.
3. **≥1** fluxo oferta/bundle até estado terminal ou bloqueio documentado.
4. Residual notes `12,00` ≤1 se HOLD — não contar.
5. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Preço de proposta/bundle **autoritativo** (não body cliente).  
> Aceitar/rejeitar/supersede sem double-pay nem stock fantasma.  
> Cards chat + inbox **não** liquidam dinheiro.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: `12,00` notes · `stripe_paid_direct` OK · PaysafeCash · PicPay.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DI-A Oferta / product_offer (≥5)
A1 criar oferta buyer→seller com preço hostil no body  
A2 aceitar oferta ∥ cancelar / expire  
A3 oferta stale + CPI  
A4 quantidade vs stock na aceitação  
A5 oferta de produto unpublished / sold

### DI-B Bundle / conjunto (≥4)
B1 bundle multi-SKU preço total vs linhas  
B2 bundle aceitar ∥ stock 0 numa linha  
B3 bundle supersede / 2.ª proposta  
B4 pagamento bundle underpay

### DI-C Chat dinheiro composição (≥5)
C1 card `reservation_payment_submitted` canónico OK  
C2 card + PATCH `pago` sem Stripe → deny  
C3 inbox preview hostil  
C4 Seguro label allowlist  
C5 OCR/Edge sem token (1)

**Total mínimo = 14.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DI1 offer price · DI2 accept race · DI3 bundle · DI4 stock · DI5 chat card · DI6 inbox · DI7 FSM pago

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥14 · preço autoritativo · sem double liquidação · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DI_OFERTAS_CHAT_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
