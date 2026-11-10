# FLEABER — RED TEAM CEGO BP
## Auditor independente · PÓS-FECHO BFBK · PAYOUT / WALLET / REFUND · v1

> Fechámos BFBK **P0**: idempotency NFC=NFD → 1 Transfer; `is_hand` allowlist exacta (sem LIKE). Hostile BFBK PASS.  
> **Poço:** ainda 2 Transfers, mint ledger, refund/release mentiroso?  
> Staging · Stripe TEST · **não corrigir**.

## CONTAGEM (obrigatório — ANTES de findings)
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = relatório INVÁLIDO.

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
**Sem TOTAL → INVÁLIDO.** O fecho começa sempre por colar esta CONTAGEM no chat.

Prefixo `RTBP-<timestamp>-` · `tool/redteam_blind_bp_<timestamp>/`.

## MISSÃO
> Ainda tiro saldo 2× ou concluido sem envio depois do fecho mão/NFC?

**Exactos BJ/AX (não contar):** NFC vs NFD · `entrega em morada` LIKE · PUT Transfer · `amount:true`.  
**Novas:** NFKC/compatibility · BOM/ZWJ na key · casefold · crash_inject · webhook replay · destination spoof · release cedo · parcial > captura · buyer refund · clawback · array amount.

## LENTES BP (7/7)
BP1 Connect/HTTP · BP2 return hijack · BP3 release+refund · BP4 Transfer/webhook · BP5 unship/FSM · BP6 actor cruzado · BP7 Δwallet.

Não ler BJ/BD/AX.

```
AUDITOR: REDTEAM_BLIND_BP_PAYOUT_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
