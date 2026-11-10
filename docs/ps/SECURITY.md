# Fleaber PS — Segurança

## Tokens

- Gerados com `gen_random_bytes(32)` — hex 64 chars
- Armazenados na BD como SHA-256 (`seller_device_tokens.token_hash`)
- Token plain só via pairing claim (TLS) — nunca em logs exportados

## PC seller

- Config em `%APPDATA%\FleaberReader\`
- Diagnóstico exporta config **redacted** (token mascarado)
- Sem screenshots enviados à cloud — OCR 100% local

## Pairing

- Código 6 dígitos, 10 min TTL
- Claim único — sessão invalidada após uso
- Validação seller_id ↔ live_id no servidor

## Edge functions

- `verify_jwt = false` — autenticação via `X-Device-Token`
- Service role apenas server-side

## RLS

- `ps_pairing_sessions` — select owner
- `ps_reader_heartbeats` — select owner/staff

## Revogação

- `batata_revoke_seller_device_token` — seller pode revogar PC antigo
