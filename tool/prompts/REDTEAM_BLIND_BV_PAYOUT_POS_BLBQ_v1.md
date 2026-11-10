# FLEABER — RED TEAM CEGO BV
## Auditor independente · PÓS-FECHO BLBQ · PAYOUT / WALLET / REFUND · v1

> Fechámos BLBQ **P2**: idempotency NFKC + strip ZWJ/BOM → 1 Transfer; `web_return` authority cru. BFBK P0 NFC=NFD já fechado. Hostile BLBQ + BFBK PASS.  
> **Poço:** ainda 2 Transfers, mint ledger, refund/release mentiroso?  
> Staging · Stripe TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = INVÁLIDO.

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N

1. P0? SIM|NÃO   2. Quantos P0: N
3. P1? SIM|NÃO   4. Quantos P1: N
5. P2? SIM|NÃO   6. Quantos P2: N
7. P3? SIM|NÃO   8. Quantos P3: N
```
**Sem TOTAL → INVÁLIDO.**

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBV-<timestamp>-` · `tool/redteam_blind_bv_<timestamp>/`.

> Ainda tiro saldo 2× ou concluido sem envio depois do fecho NFKC/ZWJ?

**Exactos BP/BJ (não contar):** ZWJ na key · NFC vs NFD `café` · `https://2130706433` · PUT Transfer · `amount:true`.  
**Novas:** casefold `Payout` vs `payout` (a app **não** lowercasa — provar 2 Transfers **ou** documentar desenho) · homoglyph cirílico na key · NBSP no meio da key · `crash_inject` sem secret · webhook Transfer replay · `destination` spoof · release sem mão · parcial > captura · buyer `refund-order` · amount `"100"` / `100.0` / array.

--------------------------------------------------
LENTES BV (7/7)
--------------------------------------------------
BV1 Connect/HTTP · BV2 return hijack · BV3 release+refund · BV4 Transfer/webhook · BV5 unship/FSM · BV6 actor cruzado · BV7 Δwallet.

Não ler BP/BJ/BD/AX.

```
AUDITOR: REDTEAM_BLIND_BV_PAYOUT_POS_BLBQ_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
