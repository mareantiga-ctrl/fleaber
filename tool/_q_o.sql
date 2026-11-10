update public.orders o
set status = 'cancelado'
where o.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and o.status = 'reserva_pendente'
  and o.live_id in (
    'f08f3776-579a-4252-9cba-b8d1626be1ca',
    'c5f71e12-6270-424a-93db-a5574d147e88'
  );
select status, count(*) from public.orders
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and created_at > now() - interval '3 days'
group by status;
