# FLEABER — RED TEAM CEGO CQ · DEEP · PÓS-ALLOWLIST
## Chat / notes / label / inbox — **quota ≥16 probes** (bypass allowlist)

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> **Proibido** pedir 24 marcas de rails novas. Atacar a **allowlist de notes**, não denylist.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL + checklist 1–8)
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

Prefixo `RTCQ-<timestamp>-` · pasta `tool/redteam_blind_cq_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**16** linhas LIVE.
2. Colunas: `probe_id | superfície | payload | HTTP/RPC | BD/inbox | HOLD|FAIL|SKIP`.
3. Controlo residual (PaysafeCash/PicPay exactos) ≤2 linhas — **não** ≥50%.
4. Sem quota → **`INCONCLUSIVO`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Bypass da **allowlist** de notes/label/inbox: o que **não** está na lista branca passa?  
> Legítimos devem continuar OK: **vazio**, `stripe_paid_direct`, texto livre **sem** €/montante.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD exactos: PaysafeCash · PicPay · esaurito · Coptic · follow unpublished.  
≥50% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### CQ-A Controlo positivo allowlist (≥3) — devem PASS/aceitáveis
A1 notes **vazias** / null  
A2 notes = `stripe_paid_direct` (ou canónico Stripe directo)  
A3 texto livre sem símbolo € e sem montante («obrigado», «já enviei»)

### CQ-B Bypass allowlist (≥8) — tentar burlar lista branca
B1 unicode € (`€` U+20AC, fullwidth `￥`/`€` lookalike) + texto inocente  
B2 **montante sem nome de rail** («12,00», «12.00 EUR», «doze euros»)  
B3 montante + emoji / ZWSP / soft-hyphen  
B4 NFKC / homóglifo que escape detector de €  
B5 notes com só dígitos + vírgula  
B6 HTML/entity `&#8364;` / `&euro;`  
B7 JSON/array em notes  
B8 notes longas + montante no meio

### CQ-C Label Seguro + inbox (≥5)
C1 label/prova em fluxo **Seguro Fleaber** com texto hostil allowlist  
C2 PATCH inbox `last_message` com bypass B*  
C3 card `reservation_payment_submitted` notes hostis  
C4 storage/upload alheio residual (1)  
C5 composição card → PATCH «pago» sem prova Stripe

**Total mínimo = 16.** Não inventar lista de 24 brands.

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
CQ1 notes allowlist · CQ2 encoding · CQ3 €/amount · CQ4 seguro/label · CQ5 inbox · CQ6 card · CQ7 Edge

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥16 · positivos A1–A3 OK · P0–P2 = **0** → `PASS_CEGO_SATURADO`. Senão `INCONCLUSIVO` / `FAIL_P*`.

```
AUDITOR: REDTEAM_BLIND_CQ_CHAT_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
