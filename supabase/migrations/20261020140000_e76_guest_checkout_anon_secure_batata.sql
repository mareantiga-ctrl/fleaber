-- =============================================================================
-- E76 — Guest checkout: EXECUTE anon em begin/revalidate COM pré-condições
-- NÃO aplicar em produção sem GO explícito (pacote hub_e76/promote_package).
--
-- Segurança (já no corpo SECURITY DEFINER — NÃO contornada):
-- 1) batata_commerce_resolve_checkout_actor:
--    - anon/sem uid → exige p_guest_token válido (resolve: not_found/revoked/expired)
--    - authenticated + guest_token → rejeita (authenticated_cannot_use_guest_token)
-- 2) batata_commerce_reservation_usable_by_actor por cada linha com reservation_request_id
--    → impede checkout de reservas de outros compradores/sessões
-- 3) Sem token → identity_required
--
-- Esta migration NÃO altera a lógica das funções — só concede EXECUTE a anon
-- nas superfícies necessárias ao percurso até pré-pagamento (sem complete/pay).
-- =============================================================================

do $$
begin
  if to_regprocedure('public.batata_commerce_resolve_checkout_actor(text)') is null then
    raise exception 'E76 abort: resolve_checkout_actor missing';
  end if;
  if to_regprocedure(
       'public.batata_commerce_reservation_usable_by_actor(uuid,uuid,uuid)'
     ) is null then
    raise exception 'E76 abort: reservation_usable_by_actor missing';
  end if;
  if to_regprocedure(
       'public.batata_commerce_checkout_begin(jsonb,text,text,jsonb,uuid,text,boolean,text)'
     ) is null then
    raise exception 'E76 abort: checkout_begin signature mismatch';
  end if;
  if to_regprocedure(
       'public.batata_commerce_checkout_revalidate(jsonb,text,uuid,text)'
     ) is null then
    raise exception 'E76 abort: checkout_revalidate signature mismatch';
  end if;
end $$;

revoke all on function public.batata_commerce_checkout_begin(
  jsonb, text, text, jsonb, uuid, text, boolean, text
) from public;
grant execute on function public.batata_commerce_checkout_begin(
  jsonb, text, text, jsonb, uuid, text, boolean, text
) to anon, authenticated, service_role;

revoke all on function public.batata_commerce_checkout_revalidate(
  jsonb, text, uuid, text
) from public;
grant execute on function public.batata_commerce_checkout_revalidate(
  jsonb, text, uuid, text
) to anon, authenticated, service_role;

revoke all on function public.batata_commerce_resolve_checkout_actor(text) from public;
grant execute on function public.batata_commerce_resolve_checkout_actor(text)
  to anon, authenticated, service_role;

-- NÃO conceder complete / confirm_off_platform / release a anon nesta ronda

notify pgrst, 'reload schema';

comment on function public.batata_commerce_checkout_begin(
  jsonb, text, text, jsonb, uuid, text, boolean, text
) is
  'E76: EXECUTE anon permitido; identidade guest via resolve_checkout_actor + usable_by_actor.';
