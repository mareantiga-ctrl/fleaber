# FLEABER — RED TEAM CEGO BJ
## Auditor independente · PÓS-FECHO ATBE · PAYOUT / WALLET / REFUND · v1

> Fechámos ATBE: Connect **só POST** cria Transfer; `amount` boolean/hex/`1e2` rejeitados; `shipped_at` = `now()` no 1.º enviado; pós-`stripe_refund_id` sem hop `enviado`/`concluido`; Edge refund devolve status BD. Hostile ATBE PASS.  
> **Poço:** ainda 2 Transfers, mint ledger, refund alheio, unship, release cedo?  
> Staging · Stripe TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
## CONTAGEM
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N
TOTAL P0–P3 abertos: N
```

**Sem TOTAL → INVÁLIDO.**

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBJ-<timestamp>-` · `tool/redteam_blind_bj_<timestamp>/`.

> Ainda consigo tirar saldo 2×, para conta errada, ou refund/release que minta?

**Exactos AX/BD (não contar):** PUT/PATCH/DELETE Transfer · `amount:true`/`0x64` · `"1e2"` · shipped_at backdate · hop pós-refund.  
**Novas:** array amount · locale vírgula · idempotency NFC/NFD · crash_inject · webhook Transfer replay · destination spoof · release sem mão · refund parcial > captura · buyer refund · clawback.

--------------------------------------------------
LENTES BJ (7/7)
--------------------------------------------------
BJ1 Connect/payout HTTP · BJ2 return hijack · BJ3 release+refund · BJ4 Transfer dup/webhook · BJ5 unship/FSM · BJ6 actor cruzado · BJ7 Δwallet/Stripe net.

Não ler AX/BD/AR/AL.

```
AUDITOR: REDTEAM_BLIND_BJ_PAYOUT_POS_ATBE_v1
production_touched: false · fase4: false · corrections_applied: false
```

Checklist 28. **NÃO CORRIGIR.**
