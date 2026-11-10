# FLEABER — RED TEAM CEGO CH · DEEP
## Auditor independente · PÓS-FECHO BXCC · PAYOUT / WALLET / REFUND / CONNECT · v1-deep

> Fechámos BXCC: Greek α/ο/ρ fold na idempotency Connect. Hostile PASS.  
> **DENSO:** matriz homógrafos + crash/webhook + release∥refund + Transfer TEST na mesma corrida.  
> Staging · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.

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
**Sem TOTAL → INVÁLIDO.**

Prefixo `RTCH-<timestamp>-` · `tool/redteam_blind_ch_<timestamp>/`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Ainda consigo **2 Transfers**, **mint wallet**, **refund>captura**, ou **desviar destination** — além do fold grego/cirílico exacto?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar exactos: Greek α/ο/ρ · Cyrillic а · NBSP na key · dual Transfer clássico já HOLD se só residual.  
Conta: Armenian/Math/fullwidth/homoglyph novos · crash_inject · webhook ordem · amount array · destination account swap · casefold design gap com prova de 2 payouts.

--------------------------------------------------
## POÇOS OBRIGATÓRIOS (≥4)
--------------------------------------------------

### POÇO CH-A — IDEMPOTENCY / CONNECT (matriz ≥8 keys)
Gerar keys que **normativamente** colidem ou duplicam Transfer. Cobrir na corrida:
- Armenian / Georgian lookalikes  
- Mathematical Alphanumeric Symbols (𝐀, 𝚊)  
- Fullwidth Latin  
- Combining marks / ZWJ / CGJ / soft hyphen  
- casefold `İ`/`i`/`I` (se aplicável)  
- key truncation / length boundary  
- parallel `Future.wait` 2× create-connect / payout mesmo intent  
Documentar: 1 vs 2 objetos Stripe; wallet Δ.

### POÇO CH-B — TRANSFER / DESTINATION / AMOUNT
1. destination = conta Stripe de outro seller  
2. amount array / negative / float string / currency mismatch  
3. payout > available balance (mint)  
4. release sem eligible; release∥refund race

### POÇO CH-C — WEBHOOK / RETURN / CRASH
1. webhook replay; sem assinatura; event antigo  
2. return URL origin spoof pós-Connect  
3. crash_inject a meio do payout (retry → duplo)  
4. seller vs buyer JWT em refund (seller-only deve manter-se)

### POÇO CH-D — WALLET FSM / COMPOSIÇÃO
1. INSERT wallet directo; UPDATE balance RLS  
2. Encadear: idempotency bypass → 2 Transfers → Δwallet vs Stripe net  
Obrigatório ≥1 Stripe Transfer ou refund **real TEST** se finding de dinheiro.

--------------------------------------------------
## LENTES CH (≥5/7)
--------------------------------------------------
CH1 Connect · CH2 return · CH3 release+refund · CH4 Transfer · CH5 FSM · CH6 actor · CH7 Δwallet

--------------------------------------------------
## TÁCTICAS MÍNIMAS
--------------------------------------------------
1. Matriz CH-A ≥8 keys.  
2. ≥1 race release∥refund ou dual payout.  
3. ≥1 destination/amount hostil.  
4. ≥1 composição Δwallet ↔ Stripe.  
5. Não enfraquecer seller-only refund na narrativa de “fix” (só reportar se abriu).

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Poços A–D · lentes ≥5 · tácticas 1–4 · senão `INCONCLUSIVO`.

```
AUDITOR: REDTEAM_BLIND_CH_PAYOUT_POS_BXCC_v1
production_touched: false · fase4: false · corrections_applied: false
VEREDICTO: FAIL_P0|FAIL_P1|FAIL_P2|FAIL_P3|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```

**NÃO CORRIGIR.**
