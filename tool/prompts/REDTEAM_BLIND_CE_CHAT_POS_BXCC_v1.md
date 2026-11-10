# FLEABER — RED TEAM CEGO CE · DEEP
## Auditor independente · PÓS-FECHO BXCC · CHAT / PROVAS / INBOX / STORAGE · v1-deep

> Fechámos BXCC: Skrill/Neteller/Paysafecard/MoneyGram/GCash/Perfect Money/enviado MB + strip U+206A/CGJ + proof `%252e`. Hostile PASS.  
> **DENSO:** esgota matriz de rails + encoding + storage + inbox na **mesma** corrida.  
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
**Sem TOTAL → INVÁLIDO.** IDs `P1-1`… = soma quantos.

Prefixo `RTCE-<timestamp>-` · `tool/redteam_blind_ce_<timestamp>/`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Ainda consigo **mentir rail de pagamento**, **colar prova fora do path**, **ler/escrever storage alheio**, ou **partir cronologia/inbox** — com variantes **fora** do denylist/canonicalizer BXCC exacto?

--------------------------------------------------
## CEGUEIRA · NÃO CORRIGIR · ACTORS
--------------------------------------------------
Não ler FROZEN BY/BS/BXCC antes do freeze. Estudar código/SQL/Edge chat/OCR/storage.  
Actors: buyer · seller · 3.º user · anon. `service_role` só fixture. Sem patch.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar exactos: Skrill · Neteller · Paysafecard · MoneyGram · GCash · Perfect Money · «enviado MB» · Clearpay+U+206A · `%252e` proof · Payoneer/ASCII rails já HOLD.  
≥50% só isto → `ATROFIA_ABORT`.

--------------------------------------------------
## POÇOS OBRIGATÓRIOS (≥4)
--------------------------------------------------

### POÇO CE-A — RAILS / COPY (matriz — esgotar lista)
Testar **cada** família abaixo (mensagem card + se existir RPC/Edge de parse). FAIL = aceite como prova de pagamento / muda FSM / liberta stock sem Stripe:
- Venmo Business / Cash App Pay / CashApp / «$cashtag»
- WeChat Pay / 微信支付 / AliPay / 支付宝 / Paytm / UPI
- Revolut Me / Wise link / Zelle / Interac e-Transfer
- Crypto: «USDT TRC20», «BTC wallet», «envia para esta wallet»
- PT/ES variantes: «já transferi MB», «comprovativo multibanco», «enviei por MBWay» (sem MB WAY oficial), «pago por transferência»
- Homógrafos: Cyrillic/Greek dentro de «PayPal» / «MB WAY» / «Clearpay»
- Zero-width / bidi / Hangul filler / soft hyphen **em rails ainda não exactos BXCC**

Documenta: quais passaram denylist, quais falharam, prova (status order / card aceite).

### POÇO CE-B — ENCODING / URL / PATH
1. `%c0%ae%c0%ae` · `%2e%2e%2f` · double-encode triplo · unicode `．．/`  
2. bidi override no path de prova (`\u202E`, RLO)  
3. `file://` · `javascript:` · data URL em card  
4. URL que aponta storage bucket alheio / path `disputes/` de outro order

### POÇO CE-C — STORAGE / OCR / EDGE
1. Upload prova em path alheio; overwrite; list bucket  
2. OCR Edge: token após kick; token de outro chat; replay  
3. Edge que «confirma» pagamento só com texto/OCR sem Stripe

### POÇO CE-D — CRONOLOGIA / INBOX / CROSS-USER
1. Inserir card no meio da timeline (ordem errada) via RPC/PostgREST  
2. Inbox: ler thread alheia; marcar lida alheia; push payload hostil  
3. 2.º buyer injeta mensagem no chat de A–B

### POÇO CE-E — COMPOSIÇÃO
Rail mentiroso ou prova path → estado `pago` / release / Δwallet ou stock. Sem composição tentada → não saturado.

--------------------------------------------------
## LENTES CE (≥6/8)
--------------------------------------------------
CE1 cards · CE2 encoding · CE3 cronologia · CE4 URLs · CE5 inbox · CE6 storage · CE7 cross-user · CE8 Edge/OCR

--------------------------------------------------
## TÁCTICAS MÍNIMAS
--------------------------------------------------
1. Matriz CE-A: **≥8** strings distintas testadas (não 1).  
2. ≥1 path encoding (CE-B).  
3. ≥1 storage ou OCR tentativa (CE-C).  
4. ≥1 cross-user (CE-D).  
5. Evidência: screenshot/API response + estado BD.

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Poços A–E · lentes ≥6 · tácticas 1–4 · CONTAGEM coerente · anti-atrofia OK → senão `INCONCLUSIVO`.

```
AUDITOR: REDTEAM_BLIND_CE_CHAT_POS_BXCC_v1
production_touched: false · fase4: false · corrections_applied: false
lentes_cobertas: […] · pocos_tentados: […]
VEREDICTO: FAIL_P0|FAIL_P1|FAIL_P2|FAIL_P3|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```

**NÃO CORRIGIR.**
