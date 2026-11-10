-- Liberar holds mortos da live anterior (aceites sem pagar + orders reserva_pendente)
-- para a Mariana poder pagar o saco da live actual sem stock fantasma.

update public.live_reservation_requests r
set status = 'cancelled',
    updated_at = now(),
    seller_note = coalesce(seller_note,'') || ' [batata: cancel stale accepted after live ended / bag pay on newer live]'
where r.status = 'accepted'
  and r.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and r.live_id = 'f08f3776-579a-4252-9cba-b8d1626be1ca';

update public.orders o
set status = 'cancelled',
    updated_at = now()
where o.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and o.status = 'reserva_pendente'
  and o.live_id in (
    'f08f3776-579a-4252-9cba-b8d1626be1ca',
    'c5f71e12-6270-424a-93db-a5574d147e88'
  );

-- Simular stock como Mariana (JWT uid)
select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('role', 'authenticated', true);

select li.ref_code,
  public.batata_live_item_total_qty(li.id) as total_qty,
  public.batata_live_item_stock(li.id)->>'available_qty' as available_qty,
  public.batata_live_item_stock(li.id)->>'blocked_qty' as blocked_qty,
  public.batata_live_item_stock(li.id)->>'ok' as ok
from public.live_items li
where li.live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
order by li.ref_code;
