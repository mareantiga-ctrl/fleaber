# FLEABER — RED TEAM CEGO DK · DEEP · PÓS-DBDG
## RLS / storage / FSM encomenda — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Ataques de **autorização e estados** — não FOMO/rails.

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

Prefixo `RTDK-<timestamp>-` · pasta `tool/redteam_blind_dk_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**14** linhas.
2. Colunas: `probe_id | actor | recurso | HTTP/RPC | BD | HOLD|FAIL|SKIP`.
3. **≥1** encomenda Stripe TEST paga para FSM pós-pago.
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Buyer **não** marca `pago` / não lê storage alheio / não PATCH money fields.  
> FSM: transições ilegais deny; stock coerente em cancel/refund/devoluçaõ.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: buyer PATCH pago 403 clássico · proof path alheio 403 · PaysafeCash.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DK-A RLS / IDOR (≥5)
A1 PATCH order alheia (status/money/shipping)  
A2 GET/SELECT storage object outro buyer  
A3 upload path `order_proofs/{outro}/`  
A4 chat_messages noutro chat  
A5 profiles / follows spoof follower_id

### DK-B Money fields / immutability (≥4)
B1 PATCH `amount_paid_cents` / `stripe_*` buyer  
B2 PATCH `payment_method` após Session  
B3 seller marca pago off-platform sem prova vs com prova  
B4 contract_unit / qty immutability

### DK-C FSM + stock (≥5)
C1 `reserva_pendente` → `enviado` saltar pago → deny  
C2 cancelado restaura stock (plataforma vs off)  
C3 refund → stock +1 não ×2  
C4 disputa aberta bloqueia release wallet  
C5 2.ª disputa mesma order → 409

**Total mínimo = 14.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DK1 IDOR · DK2 storage · DK3 money immutable · DK4 FSM · DK5 stock · DK6 disputa · DK7 actor seller/buyer

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥14 · IDOR hold · FSM coerente · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DK_RLS_STORAGE_FSM_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
