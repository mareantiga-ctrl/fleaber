# Fleaber PS Reader — Plano de implementação

> Projecto Spy (PS) — versão completa utilizável por seller normal.
> Última actualização: 2026-07-14

## Objectivo

Programa Windows **Fleaber PS Reader** — GUI, emparelhamento simples, OCR local, parser PT robusto, fila unificada Fleaber.

## Fases (execução autónoma)

### Fase A — Backend v2 ✅ em curso
- [x] Auditar MVP (`live_cross_channel_ingest_batata.sql`, edge, reader CLI)
- [ ] `ps_pairing_sessions` + RPC create/claim
- [ ] `batata_resolve_live_item_ref_v2` (ref alfanumérica + slot público)
- [ ] `batata_ingest_ocr_reservation_v2` (ref_slug, qty, confianças separadas)
- [ ] `batata_ps_live_context` (catálogo, activo, slots)
- [ ] Heartbeat reader + colunas confiança

### Fase B — Edge functions
- [ ] `ingest-ocr-reservation` v2 (compatível v1)
- [ ] `ps-pairing-claim`
- [ ] `ps-heartbeat`
- [ ] `ps-live-context`

### Fase C — Aplicação Windows (`tool/fleaber_ps_reader/`)
- [ ] GUI CustomTkinter (emparelhar, calibrar, iniciar, rever, diagnóstico)
- [ ] Captura ROI multi-monitor + calibração visual
- [ ] OCR: OpenCV preprocess + Tesseract (primário) + fallback opcional
- [ ] Tracking comentários (linhas, scroll, dedupe)
- [ ] Parser v2 + context engine + corpus testes
- [ ] LLM local opcional (Ollama) para ambiguidades
- [ ] Fila offline + retry idempotente
- [ ] Export diagnóstico ZIP

### Fase D — Studio Fleaber (Dart)
- [ ] Emparelhamento código 6 dígitos + QR
- [ ] Estado Reader online/offline (heartbeat)
- [ ] Rever / Corrigir / Ignorar com ref alfanumérica
- [ ] Detalhe origem + confianças

### Fase E — Empacotamento
- [ ] PyInstaller → `FleaberPSReader.exe`
- [ ] Script Inno Setup / NSIS
- [ ] Tesseract bundled ou instalador auxiliar

### Fase F — Testes + documentação
- [ ] pytest (parser, refs, dedupe, ingest mock)
- [ ] `docs/ps/*` completo
- [ ] `TEST_REPORT.md` com resultados reais

## Decisões técnicas

| Tema | Decisão |
|------|---------|
| GUI | CustomTkinter (leve, PyInstaller-friendly) |
| OCR primário | Tesseract + OpenCV preprocess (binarização, upscale, sharpen) |
| OCR secundário | PaddleOCR opcional se instalado (não obrigatório no instalador) |
| Emparelhamento | Código 6 dígitos, 10 min TTL, claim único |
| Ref resolution | `batata_normalize_ref` exacto → slot público → título único → ambíguo→Rever |
| LLM | Ollama HTTP local, opt-in, fallback Rever |
| Config | `%APPDATA%/FleaberReader/` + token em ficheiro encriptado simples |
| Compat | Edge/RPC aceitam v1 (`ref_number`) e v2 (`ref_slug`) |

## Critérios de aceitação

Ver secção 31 do brief utilizador — 25 itens. PASS só com testes automáticos + build exe testado.

## Não regressar

Live App, fila, stock, Hub, player live, carrossel Arena — alterações PS isoladas.
