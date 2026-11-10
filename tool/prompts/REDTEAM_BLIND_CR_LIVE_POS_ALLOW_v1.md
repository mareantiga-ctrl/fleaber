# FLEABER — RED TEAM CEGO CR · DEEP · PÓS-ALLOWLIST
## Live / FOMO / system msg — **quota ≥12 probes** (bypass stems + legítimo OK)

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> BATATA: sem redesign player/Arena/Mux layout. Atacar **allowlist/stems FOMO**, não sinónimos IT/DE/FR já fechados.

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

Prefixo `RTCR-<timestamp>-` · pasta `tool/redteam_blind_cr_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | payload | RPC/HTTP | buyer GET | HOLD|FAIL|SKIP`.
3. **≥1** system msg **legítima** welcome (deve continuar a funcionar).
4. Controlo residual `esaurito` / stems CDCI ≤2. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Bypass de **stems FOMO** com linguagem **nova** (fora da stem list, se existir).  
> Mensagem de sistema **welcome** legítima **tem** de continuar OK. Staff/hitch residual só se aberto.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: PaysafeCash · PicPay · **esaurito** · Coptic · follow unpublished.  
≥50% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### CR-A Controlo positivo (≥2)
A1 `batata_live_system_message` **welcome** / boas-vindas canónica → buyer vê, `ok:true`  
A2 system msg neutra não-FOMO («directo a começar») → OK

### CR-B Bypass stems (≥6) — língua/forma **fora** da lista conhecida
B1 ES/PT-BR FOMO novo («último disponible», «já foi») ≠ stems IT/DE/FR  
B2 NL/PL/RO scarcity curto  
B3 emoji-only scarcity (🔥1️⃣) sem palavra stem  
B4 spaced/ZWJ stem conhecido (controlo mínimo 1) + **2** frases novas sem stem  
B5 buyer INSERT `kind=system` FOMO  
B6 helper/staff zero-perms anuncia scarcity

### CR-C Hitch / convert / Mux residual (≥4)
C1 hitch qty>stock  
C2 convert sem PI / PI alheio  
C3 end_live ∥ accept race  
C4 playback/realtime residual (1) — sem mexer UI

**Total mínimo = 12.** FAIL FOMO = `ok:true` + row system visível a buyer sem convert pago.

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
CR1 welcome OK · CR2 stem bypass · CR3 FOMO · CR4 hitch · CR5 convert · CR6 race · CR7 Mux

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · A1 welcome OK · P0–P2 = **0** → `PASS_CEGO_SATURADO`. Senão `INCONCLUSIVO` / `FAIL_P*`.

```
AUDITOR: REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
