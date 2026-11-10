# Fleaber PS — Problemas conhecidos

## v1.0.0

1. **SQL v2** — `ps_reader_v2_batata.sql` deve ser aplicado em staging antes de pairing/ingest v2.
2. **Tesseract** — não incluído no instalador; seller instala via winget.
3. **PaddleOCR** — não bundled; Tesseract é primário.
4. **EXE** — spec PyInstaller criado; build não validado em VM limpa nesta sessão.
5. **QR code** — pairing mostra código numérico; QR no Studio é melhoria futura.
6. **OCR Facebook** — qualidade depende de tema, escala Windows e fonte; calibração crítica.
7. **Número só** («3») — entra com `needs_review` por desenho (sem verbo de reserva).

## Melhorias opcionais

- Heartbeat visível no Studio (RPC existe; UI badge pendente)
- Menu revogar dispositivos
- Auto-update servidor
- Corpus OCR com screenshots reais FB
