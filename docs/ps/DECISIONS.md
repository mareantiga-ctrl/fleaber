# Fleaber PS — Decisões técnicas

## 2026-07-14 — Arranque PS completo

### D1 — GUI: CustomTkinter
**Porquê:** Aparência moderna, dependências leves, empacota bem com PyInstaller. PyQt6 seria mais pesado para instalador seller.

### D2 — OCR primário: Tesseract + OpenCV
**Porquê:** Previsível offline, ~50 MB com `por.traineddata`, funciona em Windows limpo. PaddleOCR (~500 MB modelos) fica **opcional** — detectado em runtime se `paddleocr` instalado.

### D3 — Resolução de referências
Prioridade server-side (`batata_resolve_live_item_ref_v2`):
1. `batata_normalize_ref(ref_slug)` exacto no catálogo live
2. Match display `ref_code` case-insensitive
3. `public_slot` exacto (ordinal ou coluna override)
4. Alias seller (`live_item_aliases` futuro — slot = ordinal por agora)
5. Título normalizado se match único
6. Ambíguo → `needs_review`, **nunca** slot parcial de `004/21` → artigo 4

### D4 — Emparelhamento
Código 6 dígitos, TTL 10 min, gerado no Studio, claim no PC. Substitui `reader.py setup` manual.

### D5 — LLM
Ollama `http://127.0.0.1:11434` opt-in. Sem Ollama → casos ambíguos vão para Rever. Sem download silencioso de modelos.

### D6 — Confiança
Campos separados: `ocr_confidence`, `parser_confidence`, `item_match_confidence`, `identity_confidence`. Thresholds configuráveis no PC (`settings.json`).

### D7 — Compatibilidade
RPC v2 aceita `ref_number` (legado) OU `ref_slug`. Edge mantém compat v1.

### D8 — Instalador
PyInstaller one-folder + script PowerShell instalador (atalho Desktop). Tesseract incluído em `tool/fleaber_ps_reader/vendor/tesseract/` ou PATH sistema.
