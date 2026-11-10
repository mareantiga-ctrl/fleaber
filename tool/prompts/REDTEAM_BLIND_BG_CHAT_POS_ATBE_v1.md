# FLEABER — RED TEAM CEGO BG
## Auditor independente · PÓS-FECHO ATBE · CHAT / PROVAS / UI · v1

> Fechámos ATBE chat: denylist Klarna/iDEAL/Twint/Afterpay/Google Pay/…; `proof_url` amarrado a `order_proofs/{buyer}/{order_id}/`; dispute proofs bound. Hostile ATBE PASS.  
> **Poço:** mentira de pagamento / URL alheia / inbox ainda passa com variantes **novas**.  
> Staging · TEST · **não corrigir**.

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

**Sem TOTAL → INVÁLIDO.** VEREDICTO derivado da CONTAGEM.

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBG-<timestamp>-` · `tool/redteam_blind_bg_<timestamp>/`.  
Actors JWT + anon. `service_role` só fixture.

> Ainda consigo colar prova alheia, mentir rail, ou forjar inbox depois do denylist ATBE?

**Exactos BA/AU (não contar):** Klarna label · iDEAL notes · proof_url order alheio exact path.  
**Novas:** Affirm/Cash App/Pix emoji · homoglyphs novos · `object/authenticated` bucket errado · signed URL expirada reutilizada · PATCH metadata card · delete/cronologia · storage list cross-user · OCR Edge.

--------------------------------------------------
LENTES BG (8/8)
--------------------------------------------------
BG1 cards · BG2 encoding · BG3 cronologia · BG4 URLs · BG5 inbox/delete · BG6 storage · BG7 cross-user · BG8 Edge OCR/checkout.

Não ler AU/BA/AO/AI. Estudar guards chat SQL + Flutter cards OK.

```
AUDITOR: REDTEAM_BLIND_BG_CHAT_POS_ATBE_v1
production_touched: false · fase4: false · corrections_applied: false
```

Checklist 28. **NÃO CORRIGIR.** `FROZEN_REPORT.md` com CONTAGEM + TOTAL no topo.
