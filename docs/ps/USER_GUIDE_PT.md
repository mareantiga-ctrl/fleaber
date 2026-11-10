# Fleaber PS Reader — Guia do utilizador (Portugal)

## O que é

O **Fleaber PS Reader** lê comentários do Facebook Live no teu PC e envia reservas automaticamente para a fila Fleaber — juntamente com reservas da app.

## Instalação (uma vez)

1. Executa `tool\fleaber_ps_reader\install.ps1` (PowerShell).
2. Instala **Tesseract OCR** se o instalador avisar:  
   `winget install UB-Mannheim.TesseractOCR`
3. Abre o atalho **Fleaber PS Reader** no ambiente de trabalho.

## Antes de cada live

### 1. Emparelhar

1. No **Studio Fleaber** (telemóvel): ⋮ Mais → **Emparelhar PS Reader**.
2. Aparece um **código de 6 dígitos** (válido 10 minutos).
3. No PC: abre Fleaber PS Reader → **Emparelhar live** → introduz o código.
4. Confirma o nome da live.

### 2. Calibrar zona do chat

1. Abre o Facebook Live no PC (chat visível).
2. No Reader: **Seleccionar zona chat**.
3. Arrasta um rectângulo à volta dos comentários.
4. **Testar leitura OCR** — verifica se vês os comentários listados.
5. **Guardar**.

### 3. Iniciar

1. Clica **▶ Iniciar**.
2. Deixa o programa aberto durante o directo.
3. As reservas aparecem no Studio com badge **Facebook**.

## O que os compradores podem escrever

| Comentário | Resolve para |
|------------|--------------|
| Maria quero o **004/21** | Referência exacta `#004/21` |
| quero o **1** | Slot público 1 (1.º artigo) |
| quero **esse** | Artigo activo no Studio |
| **A15** / **L-32** | Referências alfanuméricas |
| **3** (só número) | Slot 3 → vai para **Rever** |

## Rever ambiguidades

No Studio, reservas com confiança baixa aparecem assinaladas:

- **Confirmar** — aceita a sugestão
- **Corrigir** — escolhe artigo/ref correcta
- **Ignorar** — descarta

## Parar

**⏸ Pausar** ou **⏹ Parar** quando terminares o directo.

Para nova live: **Emparelhar** de novo (novo código no Studio).

## Diagnóstico

Se algo falhar: **Exportar diagnóstico** → envia o ZIP à equipa Fleaber (sem tokens).

## Ollama (opcional)

Definições → activar Ollama para casos ambíguos. Requer [Ollama](https://ollama.com) instalado localmente. Sem Ollama, casos incertos vão para Rever.
