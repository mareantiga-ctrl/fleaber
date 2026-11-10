select public.batata_ref_history_pool_base_qty(
  '86d66df2-750e-486d-9c2b-79220744a2d2'::uuid,
  '46a20ad2-0c44-4fb9-9f30-d68481d616b6'::uuid
) as pool_base;

select r.status, r.requested_qty, r.live_id, li.ref_code, li.id as live_item_id,
       r.buyer_id::text, r.source
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where coalesce(li.logical_item_id, li.id) = '46a20ad2-0c44-4fb9-9f30-d68481d616b6'
  and r.status in ('pending','accepted')
order by r.created_at;

select o.status, o.quantity, o.live_id, o.product_id, o.live_item_id, o.buyer_id
from public.orders o
where o.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and coalesce(o.status,'') not in ('cancelado','cancelled','rejected','expired')
  and o.created_at > now() - interval '7 days'
order by o.created_at desc
limit 20;
