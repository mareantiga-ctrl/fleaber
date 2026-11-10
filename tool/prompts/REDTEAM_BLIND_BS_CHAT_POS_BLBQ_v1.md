# FLEABER — RED TEAM CEGO BS
## Auditor independente · PÓS-FECHO BLBQ · CHAT / PROVAS / UI · v1

> Fechámos BLBQ chat: Clearpay/Shop Pay/Strike/Sezzle/Bancontact/Zelle notes+inbox; `proof_url` canónico sem `../`; card `meta` extra recusado; fullwidth/cirílico no normalize. Hostile BLBQ PASS.  
> **Poço:** mentira de pagamento / URL / inbox com variantes **novas** (não a lista Clearpay).  
> Staging · TEST · **não corrigir**.

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
Prefixo `RTBS-<timestamp>-` · `tool/redteam_blind_bs_<timestamp>/`.  
Actors JWT + anon. `service_role` só fixture.

> Ainda colo prova alheia ou minto rail depois do denylist BLBQ?

**Exactos BM/BG (não contar):** Clearpay/Strike notes+inbox · `proof_url` `../` · `meta` extra · Affirm/Cash App.  
**Novas:** Payoneer / Western Union / Interac / BTC / USDT / Paytm / Mercado Pago · slash unicode `／` no path · overlong UTF-8 · signed URL da **própria** outra encomenda · `object/authenticated` bucket errado · zero-width no rail · card `seguro_fleaber_paid` com rail novo · PATCH `created_at` · OCR Edge.

--------------------------------------------------
LENTES BS (8/8)
--------------------------------------------------
BS1 cards · BS2 encoding · BS3 cronologia · BS4 URLs · BS5 inbox · BS6 storage · BS7 cross-user · BS8 Edge.

Não ler BM/BG/BA/AU. Estudar guards chat OK.

```
AUDITOR: REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.** `FROZEN_REPORT.md` com CONTAGEM + TOTAL no topo.
