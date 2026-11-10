# Instalação Windows — Fleaber PS Reader

## Requisitos

- Windows 10/11
- Ligação Internet (para enviar reservas)
- Tesseract OCR com idioma **português**

## Instalação rápida

```powershell
cd C:\Users\Casa\Desktop\Fleaber\fleaber\tool\fleaber_ps_reader
powershell -ExecutionPolicy Bypass -File install.ps1
```

Isto:

1. Usa o `.venv` na raiz do repo (ou cria)
2. Instala dependências Python
3. Cria atalho **Fleaber PS Reader** no ambiente de trabalho

## Tesseract OCR

```powershell
winget install UB-Mannheim.TesseractOCR
```

Durante a instalação, selecciona **Portuguese** nos idiomas.

Verifica:

```powershell
tesseract --version
tesseract --list-langs
```

Deve listar `por` e `eng`.

## EXE standalone (opcional)

```powershell
cd tool\fleaber_ps_reader
pip install pyinstaller
pyinstaller build.spec
```

O executável fica em `dist\FleaberPSReader.exe`.

## Configuração

Guardada em:

```
%APPDATA%\FleaberReader\config.json
```

Logs:

```
%APPDATA%\FleaberReader\logs\fleaber_ps.log
```

## Desinstalar

1. Apaga o atalho do Desktop
2. Apaga `%APPDATA%\FleaberReader\`
3. (Opcional) remove `.venv` do repo
