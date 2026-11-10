update public.orders
set status = 'cancelado'
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and status = 'reserva_pendente'
  and live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9';
select count(*) as still_pending from public.orders
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and status = 'reserva_pendente'
  and live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9';
