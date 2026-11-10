-- pool base for logical
select public.batata_ref_history_pool_base_qty(
  '86d66df2-750e-486d-9c2b-79220744a2d2'::uuid,
  '46a20ad2-0c44-4fb9-9f30-d68481d616b6'::uuid
) as pool_base;

-- all holds on logical across lives
select r.status, r.qty, r.live_id, li.ref_code, li.id as live_item_id
from public.live_item_reservations r
join public.live_items li on li.id = r.live_item_id
where coalesce(li.logical_item_id, li.id) = '46a20ad2-0c44-4fb9-9f30-d68481d616b6'
  and r.status in ('pending','accepted')
order by r.created_at;
