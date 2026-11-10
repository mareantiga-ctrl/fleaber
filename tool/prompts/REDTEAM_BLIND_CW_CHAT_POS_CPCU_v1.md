# FLEABER — RED TEAM CEGO CW · DEEP · PÓS-CPCU
## Chat notes / label / inbox — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Allowlist notes **estrita** (só canónicos). Atacar bypass — **não** lista de rails.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco do FROZEN (INVÁLIDO sem números N)
--------------------------------------------------
**Obrigatório:** `quantos` = 0,1,2… · TOTAL = P0+P1+P2+P3 · ver `REDTEAM_CONTAGEM_OBRIGATORIO.md`
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

Prefixo `RTCW-<timestamp>-` · pasta `tool/redteam_blind_cw_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**16** linhas.
2. Colunas: `probe_id | superfície | payload | HTTP/RPC | BD/inbox | HOLD|FAIL|SKIP`.
3. Residual exacto CQ (`12,00` · `doze euros` · `&euro;`) ≤2 se HOLD — **não** contar.
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Só entram notes canónicas: vazio · `stripe_paid_direct` · `ok` · `paguei` · `pago` · `comprovativo` · `obrigado` · `já enviei` · frase comprovativo longa.  
> **Tudo o resto** (mesmo sem €) deve deny. Bypass por case/ZWSP/NFKC/JSON/type coercion?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: `12,00` · `doze euros` · emoji 💶 · PaysafeCash · PicPay.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### CW-A Positivos (≥4) — devem aceitar
A1 notes vazias  
A2 `stripe_paid_direct`  
A3 `obrigado` / `já enviei`  
A4 `comprovativo anexo` / frase canónica longa

### CW-B Bypass allowlist (≥8)
B1 case / acentos em canónico (`Paguei`, `OBRIGADO`)  
B2 canónico + ZWSP / NBSP no meio  
B3 canónico + sufixo inocente (`ok por favor`)  
B4 texto livre sem € **não** canónico («tudo bem», «enviei agora») — esperar **deny**  
B5 JSON number / array / object em notes  
B6 HTML entity / RTL override  
B7 notes = só espaços / zero-width  
B8 type: notes como number no JSON card

### CW-C Seguro + inbox + composição (≥4)
C1 label Seguro hostil vs canónico  
C2 PATCH inbox com B4/B5  
C3 card `reservation_payment_submitted` hostil  
C4 composição → PATCH `pago` sem Stripe

**Total mínimo = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
CW1 allowlist · CW2 encoding · CW3 inbox · CW4 seguro · CW5 card · CW6 FSM · CW7 Edge

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A* OK · B* deny · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CW_CHAT_POS_CPCU_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
