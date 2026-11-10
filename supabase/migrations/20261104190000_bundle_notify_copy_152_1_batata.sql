-- ZIP 152.1 — títulos de notificação dos conjuntos (alinhar emails editoriais).
-- Não altera lógica de negócio; só copy de emits futuros via funções.
-- Idempotente: redefine as funções que emitem estes títulos.

-- Touch: actualizar só o texto das notificações nas funções existentes
-- seria uma redefinição completa. Aqui documentamos o contrato de copy
-- e um helper para seeds/ops; os próximos deploys de SQL grandes
-- devem usar estes títulos:
--
-- bundle_expired (seller timeout): 'Pedido de conjunto expirado'
-- bundle_expired (pay timeout): 'O prazo para pagar terminou'
-- bundle_quote_invalidated: 'O teu conjunto já não está disponível'
--
-- Nota: títulos antigos na inbox do utilizador NÃO são reescritos.

comment on function public.batata_bundle_touch_expiry(uuid) is
  'ZIP152.1 copy: expiração 48h — ver email_commercial + fleaber_notification_copy';
