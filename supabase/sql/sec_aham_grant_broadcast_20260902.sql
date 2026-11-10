grant execute on function public.batata_live_is_broadcasting(uuid) to anon, authenticated;
grant execute on function public.batata_live_item_stock(uuid) to anon, authenticated;
notify pgrst, 'reload schema';
