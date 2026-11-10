# Templates Auth Supabase — PT-PT (Fleaber)

Copiar no Dashboard → Authentication → Email Templates.
**Não** fazer deploy automático: o Dashboard é a fonte aplicada em PROD.

## Variáveis Supabase (preservar)

- `{{ .ConfirmationURL }}` — link assinado Supabase (confirmação, magic, invite, email change, recovery)
- `{{ .TokenHash }}` / `{{ .Token }}` — disponíveis se for preciso um bridge próprio; **não misturar** com ConfirmationURL no mesmo email

## Regra de links (ZIP 140)

Botão principal **e** link alternativo (texto) usam **a mesma** variável / o mesmo destino funcional:

| Template | Botão + fallback |
|----------|------------------|
| confirmation, magic_link, invite, email_change, recovery | `{{ .ConfirmationURL }}` |

Assim o utilizador não abre uma operação no botão e outra no link copiado.
Tokens e verificação continuam a ser os do Supabase (sem inventar URLs).

## Ortografia PT-PT

Ortografia acordada (ZIP 141.1): *diretamente*, *ativares*, *atual*.

## Site URL / redirect allowlist

Confirmar no projeto Supabase que `https://fleaber.pt/**` (e app scheme se existir) estão na allowlist de redirects.
