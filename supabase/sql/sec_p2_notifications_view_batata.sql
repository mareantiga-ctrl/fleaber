-- P2 lote 1: G-P2-01 notifications_view (anon + cross-user)
-- BUG: view sem filtro + GRANT amplo a anon → feed de favoritos alheios.
-- Preserva: seller autenticado vê favoritos dos SEUS produtos (lista_conversas).
-- production_touched: false · fase4: false

create or replace view public.notifications_view
with (security_barrier = true)
as
select
  f.id as favorite_id,
  f.created_at,
  p.seller_id as target_user_id,
  p.title as product_title,
  pr.full_name as sender_name,
  pr.photo_url as sender_photo,
  f.user_id as sender_id
from public.favorites f
join public.products p on f.product_id = p.id
join public.profiles pr on f.user_id = pr.id
where p.seller_id = auth.uid();

comment on view public.notifications_view is
  'G-P2-01: favoritos só do seller autenticado (target_user_id = auth.uid()).';

revoke all on table public.notifications_view from public, anon;
grant select on table public.notifications_view to authenticated;

notify pgrst, 'reload schema';
