# Fleaber PS — Arquitectura

## Pipeline

```
Facebook Live (browser PC)
    ↓ mss ROI capture
OpenCV preprocess → Tesseract OCR (por+eng)
    ↓ line tracking + dedupe
Parser PT v2 + LiveContext
    ↓ optional Ollama (ambiguidades)
Edge ingest-ocr-reservation
    ↓ batata_ingest_ocr_reservation_v2
live_reservation_requests (facebook_manual/ocr)
    ↓ batata_recompact_reservation_queue
Studio Fleaber — fila unificada #1 #2 #3
```

## Componentes

| Componente | Local |
|------------|-------|
| GUI Windows | `tool/fleaber_ps_reader/fleaber_ps/app/` |
| OCR | `fleaber_ps/ocr/` |
| Parser | `fleaber_ps/parser/` |
| SQL v2 | `supabase/sql/ps_reader_v2_batata.sql` |
| Edge | `supabase/functions/ingest-ocr-reservation`, `ps-pairing-claim`, `ps-heartbeat` |
| Studio | `lib/widgets/live_vendor_studio_panel.dart` |

## Resolução de referências (prioridade)

1. `batata_normalize_ref(ref_slug)` exacto
2. Display `ref_code` exacto
3. `public_slot` / ordinal catálogo
4. Título único
5. Ambíguo → `needs_review`

## Confiança

`final = 0.35×OCR + 0.35×parser + 0.20×item_match + 0.10×identity`

Threshold default auto-ingest: **0.85**

## Segurança

- Device token SHA-256 na BD
- Pairing TTL 10 min
- Sem JWT seller no PC — só device token scoped à live

## Módulos futuros (não implementados)

- Graph API Meta
- TikTok / Instagram
- PaddleOCR bundled no instalador
