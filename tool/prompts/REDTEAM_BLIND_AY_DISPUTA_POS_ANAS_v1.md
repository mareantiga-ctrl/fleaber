# FLEABER — RED TEAM CEGO AY
## Auditor independente · PÓS-FECHO ANAS · DISPUTA / ENVIO / DEVOLUÇÃO PÓS-PAGO · v1

> Fechámos ANAS disputa: seller **não** `entregue`/`concluido`; buyer **não** `concluido` em devolução; release só com envio/mão; `devolvida` só após `devolucao_entregue`; refund terminal **`devolvida`** (não `cancelado`); storage `order_proofs` **só** path com `order_id`; `proof_photos` só sign/authenticated `fleaber_private`; `return_delivered_at` gated. Hostile ANAS + AM/AHAM PASS.  
> **Poço pós-pago:** envio, disputa, devolução, stock, refund — ainda mint ou mente cronologia?  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST (captura real se P0), cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

Ver também `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: N
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P3` ou `PASS_CEGO_SATURADO` se 8/8 lentes saturadas
- P0–P3 fechados (TOTAL = 0) → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** (Session **e** pagar 4242 quando o finding exigir captura / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.** · FASE 4: **NÃO INICIAR.**

Actors: anon · buyer · seller · buyer2 · seller2 · conluio.  
`service_role` **só** fixture. Prefixo: `RTAY-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois de pago, consigo (envio/disputa/devolução) dinheiro, stock, ou estado que a UI esconde?**

Não repetir exactos AS/AM:
- seller pago→entregue exact AS-P1-02 (agora 403 — testar buyer entregue sem enviado, seller enviado→entregue hop)
- seller concluido + release exact AS-P1-05 (agora seller blocked — testar cron auto-feedback 48h, buyer release sem receção real)
- shallow order_proofs exact AS-P1-07 (agora deep only — testar dispute path, chat_media leak)
- devolvida shortcut exact AS-P2-03 (agora hop obrigatório — testar buyer pedido_devolucao sem disputa)
- refund→cancelado exact AS-P2-04 (agora devolvida — testar webhook duplo, partial refund status)
- proof_photos public exact AS-P2-07 (agora sign only — testar authenticated outro order_id)
- stock devolvida sem refund AM3 · refund shipped AM4 · INSERT resolvida AM3-P3

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta AS/AM → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AY (obrigatório 8/8)
--------------------------------------------------
| # | Lente | Pergunta-guia |
|---|--------|----------------|
| AY1 | Disputa vs FSM | Abrir/fechar em estados errados |
| AY2 | Enviado ∥ disputa | Ordem cronológica mente |
| AY3 | Devolução / stock | Restore sem refund? 2.º checkout? |
| AY4 | Refund no caos | Parcial, seller pós-release, devolvida terminal |
| AY5 | Receção ∩ disputa | Saltos buyer/seller / cron 48h |
| AY6 | Etiqueta / carrier | Enviado sem captura |
| AY7 | Prova disputa | Path/storage alheio, URLs evil |
| AY8 | Composição → Δwallet/stock/Stripe |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 order Stripe TEST **paga**.  
2. Percorrer envio → disputa → devolução (≥2 estados).  
3. Contabilidade: wallets + stock + status.  
4. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ay_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo**, repetir **`## CONTAGEM`** + **`TOTAL P0–P3 abertos`**.

```
AUDITOR: REDTEAM_BLIND_AY_DISPUTA_POS_ANAS_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AY1, AY2, AY3, AY4, AY5, AY6, AY7, AY8]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas — igual AT).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
