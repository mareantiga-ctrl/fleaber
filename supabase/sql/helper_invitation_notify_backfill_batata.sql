-- Reenviar notificações para convites pendentes sem notificação (após deploy da RPC).
-- Executar uma vez no SQL Editor, depois de criar batata_notify_helper_invitation.

insert into public.user_notifications (
  user_id,
  kind,
  title,
  body,
  actor_id,
  is_read
)
select
  h.helper_user_id,
  'helper_invitation:' || h.id::text,
  'Convite para colaborar numa loja',
  'Recebeste um convite para colaborar numa loja Fleaber.',
  h.invited_by,
  false
from public.seller_helpers h
where h.invitation_status = 'pending'
  and not exists (
    select 1
    from public.user_notifications n
    where n.user_id = h.helper_user_id
      and n.kind = 'helper_invitation:' || h.id::text
  );
