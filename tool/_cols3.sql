select column_name from information_schema.columns where table_schema='public' and table_name='product_offers' order by 1;
select to_regclass('public.product_offers') as offers;
