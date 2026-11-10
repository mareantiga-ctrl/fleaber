select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"69104e91-6a00-40d9-a7c9-b1571422ae43","role":"authenticated"}', true);
select set_config('role', 'authenticated', true);

-- try insert like the app
insert into public.orders (
  product_id, buyer_id, seller_id, price_total, shipping_method, payment_method,
  status, is_reservation, quantity, live_id, live_item_id
) values (
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d',
  '69104e91-6a00-40d9-a7c9-b1571422ae43',
  '86d66df2-750e-486d-9c2b-79220744a2d2',
  59.91,
  'Envio Transportadora (€3.50)',
  'Pagamento na App',
  'reserva_pendente',
  false,
  5,
  'c3af87a7-a962-4af5-bb35-90b39a03ede9',
  'fad6c909-b066-48ee-830f-09b503146019'
) returning id, status;
