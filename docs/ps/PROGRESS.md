# Fleaber PS — Progresso

> Actualizado: **2026-07-14 19:15 UTC+1**

## Concluído v1.0

- [x] SQL v2 `ps_reader_v2_batata.sql` (pairing, refs alfanuméricas, ingest v2, heartbeat)
- [x] Edge: `ingest-ocr-reservation` v2, `ps-pairing-claim`, `ps-heartbeat`
- [x] App GUI `tool/fleaber_ps_reader/` (CustomTkinter)
- [x] Parser v2 + refs `004/21`, slots, deícticos, quantidades
- [x] OCR pipeline (OpenCV + Tesseract + dedupe + offline queue)
- [x] Studio: emparelhamento código 6 dígitos
- [x] Testes: **23/23 PASS**
- [x] Docs `docs/ps/*`
- [x] `install.ps1` + `build.spec` PyInstaller

## Deploy staging

- [ ] Aplicar `ps_reader_v2_batata.sql` (requer `supabase link`)
- [ ] Deploy edge functions
- [ ] APK seller rebuild

## Testes humanos

- [ ] Bateria final (aguarda deploy + instalador)

## Próxima tarefa

Deploy staging + validação E2E com seller.
