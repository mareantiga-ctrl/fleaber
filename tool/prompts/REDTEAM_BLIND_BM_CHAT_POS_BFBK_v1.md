# FLEABER — RED TEAM CEGO BM
## Auditor independente · PÓS-FECHO BFBK · CHAT / PROVAS / UI · v1

> Fechámos BFBK: Affirm/Cash App/Pix denylist; `proof_url` needle **só no path** (não query); inbox forge alargado. Hostile BFBK PASS.  
> **Poço:** mentira de pagamento / URL / inbox com variantes **novas**.  
> Staging · TEST · **não corrigir**.

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

Prefixo `RTBM-<timestamp>-` · `tool/redteam_blind_bm_<timestamp>/`.

## MISSÃO
> Ainda colo prova alheia ou minto rail depois do denylist BFBK?

**Exactos BG/BA (não contar):** Affirm label · Cash App notes · proof `?order_proofs=…` query.  
**Novas:** Clearpay/Shop Pay/Strike · homoglyphs novos · path traversal `../` · fragment `#` · signed URL de outro bucket · PATCH `created_at` · delete cronologia · chave `meta` extra · OCR Edge.

## LENTES BM (8/8)
BM1 cards · BM2 encoding · BM3 cronologia · BM4 URLs · BM5 inbox · BM6 storage · BM7 cross-user · BM8 Edge.

Não ler BG/BA/AU. Estudar guards chat OK.

```
AUDITOR: REDTEAM_BLIND_BM_CHAT_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
