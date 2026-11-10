# Fleaber PS — handoff (agente)

> **Actualizar sempre** após: nova bateria/teste, fix, mudança de gatilho IA, sync gold, deploy SQL/edge, bump de versão da ext.  
> Regra Cursor: `.cursor/rules/ps-handoff-update.mdc`  
> Última actualização: **2026-07-23** · ext **v1.5.36**  
> **S-LIVE-X:** script `lab2_s_live_cross` · expectPanes · CHECKPOINT · `POST /ps_ai/lab2/bot_sim`  
> Cue Lab limitado à coluna Chat. FEITO nunca fecha Passos com remaining>0.

## Snapshot

| Item | Estado |
|------|--------|
| **Lab v2 Fase 1** | **ENTREGUE** — 4 painéis, scripts, navigate, shot meta, export ZIP |
| **Lab Passos / Confirm** | **NOVO 1.5.30** — `runCorpusConfirmLoop` + `/ps_ai/lab2/fm_snapshot` |
| PS junk/ref | Pedidos OK; nomes 1.5.28 risco residual (sem reteste) |
| Espelho TCL 100% | **Lab v2 painel 1** — ADB screencap (serial `a698f0de`). Liga USB. |
| Bots Face | **Fase 2** |
| FM | limpar sempre antes/depois |


### Modo de trabalho (utilizador)

### Auditoria passo a passo (obrigatório)

`live_reservation_requests` **colapsa** supersede → no fim só ficam poucas linhas.  
Para ver **todos** os comentários **sem o utilizador mandar ficheiros**:

1. Harness com `Start-PsTestSession.ps1` / `Start-FaceDomHarness.ps1` → `tool/ps_ai/runs/published_*.json`
2. Extensão actual → `tool/ps_ai/runs/telemetry_*.jsonl`
3. `node tool/ps_ai/analyze_srj_run.mjs` (srj) ou analyze_latest_sr_run
4. Limpeza FM após análise

### Throughput (PS sob pico)

**Problema:** ~1 comentário/s com IA síncrona → a extensão perdia comentários (marcava “visto” antes do ACK).  
**Resolução v1.5.7 (aplicada):** fila persistente + até 2 workers + **só marca visto depois da BD confirmar**; se falhar, volta a tentar. A IA **não acelera** o ritmo — **aumenta precisão**; a fila garante que **não se perde** volume. Delay harness por defeito **2500 ms**.

### IA (Ollama)

Prova concreta: ficheiro `telemetry_*.jsonl` com `ollama_called:true` e `ollama_ok:true|false`. Sem isto = falha de instrumentação, não “talvez”.  
CORS: `Setup-OllamaForPs.ps1`.
---

## 1. O que é o PS

### Sim vs extensão vs BD

| | Offline parser | Harness DOM | Face real |
|--|----------------|-------------|-----------|
| Parser | `parser.js` | mesmo | mesmo |
| DOM scan | — | mesmo `content.js` | mesmo |
| Comentários | JSONL | inject no DOM | pessoas / Meta API |
| Test Users | — | **não precisa** | bloqueados a criar |

### Meta / App Review (estado 2026-07-16)

- App Fleaber: Business verification **OK**; App Review **não** — falta ícone 1024, Privacy Policy URL, categoria (`Currently ineligible for submission`)
- Test Users: **0** + create disabled
- `FACEBOOK_PAGE_TOKEN` removido do smoke env (script não usava)
- Não pedir App Review avançada (Página/Live API) nesta fase

---

## 1. O que é o PS

**Project Spy** = ler comentários de **Facebook Live** → criar/actualizar/cancelar **reservas** no Fleaber (staging).

| Camada | O quê | Onde |
|--------|-------|------|
| **A** | Parser regras PT (refs, qty, cancel, slots, OCR) | `tool/fleaber_ps_extension/parser.js` |
| **B** | Ollama local Lite/Pro + few-shot gold | `fleaber-ps-lite` / `fleaber-ps-pro` |
| **C** | Fine-tune (futuro) | quando gold ≥ 200–500 |

**Não aprende sozinho em live.** Gold cresce via sync BD ou sim offline → `build_modelfiles` → `setup_tiers`.

---

## 2. Arquitectura (fluxo)

```
Facebook DOM → content.js (scan)
  → parseCommentLine / expandMultiItemParses
  → resolveSlotToRef(catalog)
  → SessionIdentity (nome + lastRef por comprador)
  → lastQty[buyer|ref] (reduções tira)
  → [opcional] Ollama (gatilhos — ver §5)
  → ingest → edge/RPC staging
  → painel UI + (ideal) ps_panel_events
```

| Peça | Path |
|------|------|
| Ext Chrome | `tool/fleaber_ps_extension/` (manifest version) |
| Staging | `https://fxdknzrqjenzqcvnwqqq.supabase.co` |
| Gold | `tool/ps_training_gold.jsonl` |
| Catálogos baterias | `tool/ps_batteries/catalogs.json` |
| Registry lives | `tool/ps_batteries/registry.json` |
| Sync BD→gold | `tool/ps_gold_sync_from_live.dart` |
| Pipeline | `tool/ps_ai/sync_training_pipeline.ps1` |
| Sim offline | `tool/ps_ai/sim_battery.mjs` (`--ollama` = camada B) |
| Gerador ambiguo | `tool/ps_ai/generate_ambiguous_corpus.mjs` |
| Gerador lusófono | `tool/ps_ai/generate_lusophone_corpus.mjs` |
| Gerador HARD (títulos parecidos) | `tool/ps_ai/generate_hard_corpus.mjs` |
| Gerador Face junk ~1000 | `tool/ps_ai/generate_face_junk_corpus.mjs` |
| Gerador max-ambiguity (+pass2) | `tool/ps_ai/generate_max_ambiguity_corpus.mjs` |
| Simulador chat Face (DOM) | `tool/ps_ai/face_dom_harness/` + `Start-FaceDomHarness.ps1` |
| Meta Test Users + comments | `tool/ps_ai/Invoke-MetaFaceCommentSmoke.ps1` (bloqueado sem Test Users) |
| Roster nomes/homónimos | `tool/ps_ai/am_meta_test_user_roster.json` |
| Ingest sim → BD staging | `tool/ps_ai/ingest_sim_to_staging.mjs` |
| Loop treino | `tool/ps_ai/run_offline_training.ps1` |
| Audit BD | `tool/ps_live_watch_audit.dart` |
| SQL painel | `supabase/sql/ps_panel_events_batata.sql` (deploy staging?) |

**Buyers QA:** Cláudia Monteiro · Cláudia João · 3º via Chrome build.  
**Refs por bateria:** RF1–3 · TT1–3 · CA1–3 · CB1–3.

---

## 3. Política de produto (IA) — intenção do utilizador

Decisão **do utilizador** (não atalhar):

1. Se **mesmo comprador** envia **2+ msgs sobre o mesmo artigo** → **IA deve entrar** (com estado: lastRef + lastQty).
2. Se **não há ~100% certeza** de qual artigo → **IA deve entrar**.
3. Em `tira N REF`, a IA **tem de receber qty anterior**; sem estado a IA é inútil → **passar `buyer_qty_state`** ao Ollama.
4. O apertão v1.4.2 (`confiança ≥ 0.75` + ref → nunca IA) foi **decisão do agente** para parar spam com Ollama offline — **não pedido pelo utilizador**; insuficiente como prova. Revertido/afrouxado em v1.4.4.

---

## 4. Histórico baterias (resultados)

| Bateria | Live (staging) | Resultado | Notas |
|---------|----------------|-----------|-------|
| **RF** | `0671a0dc-…` | Parcial | Parser A melhorou slots/qty; João `quero rf1` quase não chegou BD; gold RF-01..12 |
| **TT** | `02598fb2-…` | Mau (IA 0) | Gatilho continuidade → Ollama falhou em tudo; BD ~9 linhas; identidade «Monteiro inafinal» fantasma; gold TT corrigido |
| **CA** | `ba2f35e8-…` | Quase vazio | Face **anti-spam** após 1º `quero CA1` (Monteiro); gold CA-01 |
| **CM lusófono 600** | offline `cm_lusophone_600.jsonl` | parser_only **553/5** | Ver §4b — **sem** `--ollama` nesta medição |
| **HS hard 120** | offline `hs_hard_120.jsonl` | A+B feitos | Ver §4c — artigos nomes quase iguais |

### 4b. Resultados CM offline (agente — sem Face)

**Data:** 2026-07-16  
**Comando:** `node tool/ps_ai/sim_battery.mjs tool/ps_batteries/cm_lusophone_600.jsonl`  
**Modo:** `parser_only` (`ollama_flag: false`) · Ext **v1.4.6**

| Métrica | Baseline (pré-fix) | Após v1.4.5 qty | **Agora v1.4.6** |
|---------|---------------------|-----------------|------------------|
| PASS (com expected) | 373 | 473 | **553** |
| FAIL | 174 | 77 | **5** |
| PARSE_NULL | 18 | 16 | 6 |
| Gold RF/TT eval | 27 PASS | 27 PASS | **27 PASS / 0 FAIL** |
| IA (Ollama) | — | — | **não usada nesta corrida** |

**FAIL restantes (5):** cold-start sem lastRef do buyer (`afinal quero 5`, `lewa esse`, …) — seed/Ollama cobrem; **não pedir Face**.

**Fixes v1.4.6:** `me vê`/`da-me`/`troca pra`; reduce colado; `ja nao kero`; slot `so quero 3`/`bota 2`; lastRef só catálogo.

### 4c. Bateria HS hard 120 — **120/120**

Ext v1.4.7+ · títulos semelhantes.

### 4d. FX Face junk 1000 + BD assert **completo** (2026-07-16)

**Corpus:** `tool/ps_batteries/fx_face_junk_1000.jsonl` · Ext **v1.4.9**

| Parser | PASS | FAIL |
|--------|-----:|-----:|
| parser_only | **996** | **0** |

**BD — todas as PASS ingeríveis (não amostra):**  
`node tool/ps_ai/ingest_sim_to_staging.mjs --all --fresh`

| | |
|--|--|
| Live | `181c818a-e71f-416b-80a6-f6da3a53ff98` |
| Candidatos (PASS + ref válida) | **986** (887 reserve + 99 cancel; multi/ghost excl.) |
| Ingest OK | **986/986** |
| Assert passo-a-passo (ref+qty ou cancel) | **986/986** · `bd_all_match: true` · **0 mismatch** |
| Relatório | `tool/ps_ai/sim_ingest_fx_report.json` |
| Log consola | `tool/ps_ai/sim_ingest_fx_full_console.log` |

Cada um dos 986: após ingest → ler BD por `idempotency_key` → comparar esperado.  
(Na live ficam ~93 rows “visíveis” porque supersede/cancel colapsa pending — o assert é **por passo**, não só o estado final agregado.)

**Ainda fora deste assert:** smoke Face real (script Meta pronto — ver topo).

### 4e. AM max-ambiguity (pass1 + pass2 forgotten) — 2026-07-16

**Gerador:** `node tool/ps_ai/generate_max_ambiguity_corpus.mjs --count 800 --battery AM`  
**Ficheiros:** `am_max_ambiguity_800.jsonl` + `am_pass2_forgotten_*.jsonl` → `am_combined_1103.jsonl`  
**Personas:** 23 (homónimos Ana/Cláudia/Maria + nomes parecidos + photo keys)  
**Artigos:** AM1–AM6 (incl. Vintage vs Azul M)  
**Pass2:** negação, vintage, glued OCR, rebook pós-cancel, slot/aspas, underspecified, cross-talk

| Parser AM combined | PASS | FAIL |
|--------------------|-----:|-----:|
| v1.5.0 | **1098** | **0** |

Ext: vintage/negação/quero1AM2; regressão HS 120/0 · FX 996/0 · gold 27/0.

---

## 5. Fixes (código) e porquê

| Ver | Fix | Porquê |
|-----|-----|--------|
| 1.3.x | Painel arrastável, journal, Copiar | Ver sem prints |
| 1.3.5+ | Slot≠qty, ordinais, dígito, tira1, Face `·1min` | RF falhou `quero o 2`→ref 2 |
| 1.4.0 | Tiers Lite/Pro popup | Rollout PCs fracos/fortes |
| 1.4.1 | `gold_candidate` no panel_log | Sync gold sem copy/paste |
| **1.4.2** | Gatilho IA apertado (≥0.75 skip) + circuit breaker Ollama down | Parar flood `IA falhou` com Ollama offline — **utilizador discorda da restrição ≥0.75** |
| **1.4.3** | Multi `quero CB1 e CB2`; OCR inso/injanao/incancela; SEEN em tira-skip | CB spam painel + pedido multi-item |
| **1.4.5** | Corpus lusófono CM; `kero`/dialectos em RESERVE_VERBS; context_echo alargado; sim por `buyer_key`; IDENTITY_POLICY | Bateria Marina + PT/BR/África; homónimos offline |
| **1.4.6** | Qty BR/AO; lastRef só catálogo; HS hard + sim reporta mode/llm | CM 553/5; HS ~110 |
| **1.4.7** | `matchCatalogByTitle` / `title_resolved`; aliases HS; preservar qty se IA=1 | **HS 120/120** |
| **1.4.8** | Strip lixo Face; ecos `mais 2`; cancel qty=1; slot so quero/kero 1–3; ingest BD | FX ~988 · BD 40 ingest |
| **1.4.9** | Aspas; `qero o N`; assert BD `--all` | FX 996/0 · BD **986/986** |
| **1.5.0** | AM max-ambiguity + pass2; vintage/negação/glued; Meta smoke script + roster nomes | **AM 1098/0** |
| **1.5.3** | Liked by não come «o» de «o mesmo»; strip `in` solto | nomes / context_echo |
| **1.5.4** | Journal passos local (export popup) + SQL/edge `ps_ingest_audit` | auditoria entrada a entrada |

**Ainda aberto**

- Smoke Face real na Página 150 seguidores (comentários humanos) quando quiserem
- App Review só depois de Privacy Policy + ícone + categoria + demo
- `avatar_phash` real no DOM
- Ollama/gold append no corpus AM
- BD ingest `--all` também no AM (opcional)

---

## 6. pt99 / item_not_found

- `quero pt99` fora do catálogo → `item_not_found` = **correcto** (não inventar artigo).
- Bug: `cancela pt99` gravava CB2/CB3 → **fix v1.4.4** (ghost_ref não herda lastRef).

---

## 10. Frases «o mesmo» / «tambem» / «igual ao anterior»

**Decisão utilizador (2026-07-16): A** — a IA lê o contexto e usa o artigo certo.

- `o mesmo`, `tambem`, `mais um`, `igual ao anterior`, `esse`, … → **reserve qty 1** do **último artigo desse comprador**
- Parser: `reason=context_echo` → dispara IA com `active_ref` + `buyer_qty_state`
- Sem histórico do comprador → needs_review / não inventar ref

---

## 7. Treino offline (fase actual)

```powershell
# Gerar N frases + sim (+ Ollama) + eval + Modelfiles
powershell -File tool\ps_ai\run_offline_training.ps1 -Battery CB -Count 300
# Só parser:
powershell -File tool\ps_ai\run_offline_training.ps1 -Battery CB -Count 300 -SkipOllama
# Pós-live Face:
powershell -File tool\ps_ai\sync_training_pipeline.ps1 -LiveId UUID -Battery CB
```

Face Live = smoke identidade real. **Parser/IA/gold** = sim autónomo.

---

## 8. Checklist agente (após qualquer mudança PS)

1. Actualizar **este ficheiro** (secção 4 e/ou 5 + data/versão)
2. Se gold mudou → `eval_parser_gold.mjs` + `build_modelfiles.ps1` (+ `setup_tiers` se Ollama)
3. Bump `manifest.json` se ext mudou
4. Não remover funcionalidades PASS sem pedido (BATATA)

---

## 9. Glossário rápido

| Termo | Significado |
|-------|-------------|
| supersede | Nova qty substitui reserva pending do mesmo buyer+ref |
| reduce_delta / tira | Subtrair N à qty anterior (precisa lastQty) |
| continuity | Sem ref → último artigo **desse** comprador |
| Lite/Pro | llama3.2:3b / qwen2.5:7b + few-shot gold |
