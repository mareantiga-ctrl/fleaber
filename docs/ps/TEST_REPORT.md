# Fleaber PS — Relatório de testes

> Data: 2026-07-14

## Testes automáticos (local)

| Suite | Resultado | Detalhe |
|-------|-----------|---------|
| `tests/test_parser.py` | **PASS** | 23/23 |
| `tests/test_dedupe.py` | **PASS** | 3/3 |

### Cobertura parser

- Ref `004/21`, `#004/22`, `A15`, `L-32`
- Slots 1–999 sem confundir com refs compostas
- Deícticos («quero esse»)
- Quantidades («2 unidades do 2»)
- Cancelamentos
- Chat normal rejeitado

## Testes pendentes (requerem staging + devices)

| ID | Cenário | Estado |
|----|---------|--------|
| E2E-01 | Pairing código → ingest | Pendente SQL deploy |
| E2E-02 | OCR live Facebook real | Pendente seller |
| E2E-03 | Fila mista App + FB | Pendente |
| E2E-04 | Rever / Corrigir ref alfanumérica | Pendente APK rebuild |

## Comandos

```powershell
cd tool\fleaber_ps_reader
python -m pytest tests/ -v
```

## Dart analyze

`ps_ingest_service.dart` — PASS (0 issues após fix)
