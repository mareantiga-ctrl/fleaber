# Fleaber Reader (PS)

Agente local Windows que lê comentários Facebook via OCR e envia reservas para a **fila unificada** Fleaber.

## Pré-requisitos

1. SQL `supabase/sql/live_cross_channel_ingest_batata.sql` aplicado em staging
2. Edge function `ingest-ocr-reservation` deployada
3. [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) instalado (`por` + `eng`)
4. Token do dispositivo gerado na app (Studio live → **PS Reader**)

## Instalação

```powershell
cd tool/fleaber_reader
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## Configuração

```powershell
python reader.py setup
python reader.py calibrate
```

Config guardada em `%APPDATA%\FleaberReader\config.json`.

## Correr durante live

1. Abre Facebook Live no PC (chat visível na ROI calibrada)
2. `python reader.py run`
3. Comentários «Maria quero o 3» entram na fila do studio com badge Facebook

## Teste rápido (sem OCR)

```powershell
python reader.py test-line "Maria quero o 3"
```

## Arquitectura

```
Facebook chat (ROI) → OCR → parser PT → Edge ingest-ocr-reservation
  → batata_ingest_ocr_reservation → live_reservation_requests (facebook_manual/ocr)
  → batata_recompact_reservation_queue (#1 #2 #3 unificado)
```

Spec completa: `docs/live-cross-channel-ingest-spec.md`
