# Fleaber PS — Resolução de problemas

## O programa não abre

- Executa `install.ps1` novamente
- Verifica Python: `py -m fleaber_ps` na pasta `tool\fleaber_ps_reader`

## «Tesseract não encontrado»

```powershell
winget install UB-Mannheim.TesseractOCR
```

Reinicia o PC após instalar.

## OCR não lê nada

1. Recalibra a zona — inclui só a área dos comentários
2. **Testar leitura OCR** antes de Iniciar
3. Aumenta zoom do browser (125–150%)
4. Tema claro do Facebook costuma funcionar melhor

## Código emparelhamento inválido

- Expira em 10 min — gera novo no Studio
- Verifica SQL v2 deployado em staging

## Reservas não aparecem no Studio

1. Confirma emparelhamento (live correcta)
2. Exporta diagnóstico
3. Verifica Internet no PC
4. Rebuild APK com Studio actualizado

## «004/21» resolve artigo errado

Actualiza para PS Reader v1.0 + SQL v2. O MVP antigo só suportava slots numéricos.

## Duplicados

Normal ver «skipped» no log — dedupe activo. Se duplicado real, reporta com diagnóstico.

## Offline

Reservas ficam em `%APPDATA%\FleaberReader\offline_queue.jsonl` e reenviam ao reconectar.
