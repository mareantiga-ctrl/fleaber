-- Fleaber BATATA: apagar conta + todos os dados (APENAS staging / QA).
-- Produção: usar fluxo separado (soft delete + retenção legal) — ver comentário no fim.
--
-- Chamada: edge function delete-test-account (service_role) → staging_nuke_user_data(uuid)
-- Depois: auth.admin.deleteUser no Auth.
--
-- NÃO expor a authenticated/anon. Deploy + ALLOW_TEST_ACCOUNT_NUKE=true no projecto staging.

create or replace function public.staging_nuke_user_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_stats jsonb := '{}'::jsonb;
  v_n int;
begin
  if p_user_id is null then
    raise exception 'user_id required';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'user not found';
  end if;

  -- -------------------------------------------------------------------------
  -- Encomendas, disputas, comissões, wallet
  -- -------------------------------------------------------------------------
  delete from public.order_dispute_replies odr
  using public.order_disputes od
  where odr.dispute_id = od.id
    and od.order_id in (
      select o.id from public.orders o
      where o.buyer_id::text = p_user_id::text
         or o.seller_id::text = p_user_id::text
    );
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('order_dispute_replies', v_n);

  delete from public.order_disputes od
  where od.order_id in (
    select o.id from public.orders o
    where o.buyer_id::text = p_user_id::text
       or o.seller_id::text = p_user_id::text
  );
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('order_disputes', v_n);

  begin
    delete from public.fleaber_commissions fc
    where fc.order_id in (
      select o.id from public.orders o
      where o.buyer_id::text = p_user_id::text
         or o.seller_id::text = p_user_id::text
    );
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('fleaber_commissions', v_n);
  exception when undefined_table then
    null;
  end;

  delete from public.wallet_transactions wt
  where wt.wallet_id = p_user_id
     or wt.order_id in (
       select o.id from public.orders o
       where o.buyer_id::text = p_user_id::text
          or o.seller_id::text = p_user_id::text
     );
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('wallet_transactions', v_n);

  delete from public.orders o
  where o.buyer_id::text = p_user_id::text
     or o.seller_id::text = p_user_id::text;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('orders', v_n);

  -- -------------------------------------------------------------------------
  -- Chat marketplace
  -- -------------------------------------------------------------------------
  delete from public.chat_messages cm
  where cm.chat_id in (
      select c.id from public.chats c
      where c.user_a::text = p_user_id::text
         or c.user_b::text = p_user_id::text
    )
    or cm.sender_id::text = p_user_id::text
    or cm.receiver_id::text = p_user_id::text;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('chat_messages', v_n);

  delete from public.chats c
  where c.user_a::text = p_user_id::text
     or c.user_b::text = p_user_id::text;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('chats', v_n);

  -- -------------------------------------------------------------------------
  -- Avaliações, social, propostas, conjuntos
  -- -------------------------------------------------------------------------
  begin
    delete from public.reviews r
    where r.buyer_id::text = p_user_id::text
       or r.target_id::text = p_user_id::text;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('reviews', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.reviews_gerais rg
    where rg.buyer_id::text = p_user_id::text
       or rg.target_id::text = p_user_id::text;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('reviews_gerais', v_n);
  exception when undefined_table then
    null;
  end;

  delete from public.follows f
  where f.follower_id = p_user_id or f.following_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('follows', v_n);

  delete from public.favorites fav
  where fav.user_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('favorites', v_n);

  delete from public.product_offers po
  where po.buyer_id = p_user_id or po.seller_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('product_offers', v_n);

  begin
    delete from public.product_bundles pb
    where pb.buyer_id = p_user_id or pb.seller_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('product_bundles', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.seller_bundle_discounts sbd
    where sbd.seller_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('seller_bundle_discounts', v_n);
  exception when undefined_table then
    null;
  end;

  -- -------------------------------------------------------------------------
  -- Live: reservas, refs, staff, director, DMs, gorjetas, presença
  -- -------------------------------------------------------------------------
  delete from public.live_reservation_requests lrr
  where lrr.seller_id = p_user_id
     or lrr.buyer_id = p_user_id
     or lrr.processed_by_user_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('live_reservation_requests', v_n);

  begin
    delete from public.ref_history_audit_log rha
    where rha.seller_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('ref_history_audit_log', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.ref_histories rh
    where rh.seller_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('ref_histories', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.staff_action_logs sal
    where sal.seller_id = p_user_id
       or sal.performed_by_user_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('staff_action_logs', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.seller_helpers sh
    where sh.seller_id = p_user_id or sh.helper_user_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('seller_helpers', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.live_director_timeline_events e
    using public.live_director_runs r
    where e.run_id = r.id
      and (r.seller_id = p_user_id or r.operator_id = p_user_id);
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('live_director_timeline_events', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.live_director_audit_log e
    using public.live_director_runs r
    where e.run_id = r.id
      and (r.seller_id = p_user_id or r.operator_id = p_user_id);
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('live_director_audit_log', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.live_director_runs r
    where r.seller_id = p_user_id or r.operator_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('live_director_runs', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.live_director_sim_profiles dsp
    where dsp.profile_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('live_director_sim_profiles', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.live_director_scripts ds
    where ds.seller_id = p_user_id or ds.operator_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('live_director_scripts', v_n);
  exception when undefined_table then
    null;
  end;

  delete from public.live_private_messages lpm
  where lpm.sender_id = p_user_id or lpm.recipient_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('live_private_messages', v_n);

  delete from public.live_tips lt
  where lt.buyer_id = p_user_id or lt.seller_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('live_tips', v_n);

  delete from public.live_viewers lv
  where lv.user_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('live_viewers', v_n);

  -- Lives do vendedor (cascade: items, messages, raffles, etc.)
  delete from public.lives l
  where coalesce(l.seller_id, l.vendedor_id) = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('lives', v_n);

  -- Anúncios marketplace (cascade em favoritos já limpos)
  delete from public.products pr
  where pr.seller_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('products', v_n);

  -- -------------------------------------------------------------------------
  -- Perfil, handles, notificações
  -- -------------------------------------------------------------------------
  begin
    delete from public.profile_handle_redirects phr
    where phr.profile_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('profile_handle_redirects', v_n);
  exception when undefined_table then
    null;
  end;

  begin
    delete from public.profile_handle_claim_log phc
    where phc.profile_id = p_user_id or phc.actor_id = p_user_id;
    get diagnostics v_n = row_count;
    v_stats := v_stats || jsonb_build_object('profile_handle_claim_log', v_n);
  exception when undefined_table then
    null;
  end;

  delete from public.user_notifications un
  where un.user_id = p_user_id or un.actor_id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('user_notifications', v_n);

  delete from public.wallets w where w.id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('wallets', v_n);

  delete from public.profiles p where p.id = p_user_id;
  get diagnostics v_n = row_count;
  v_stats := v_stats || jsonb_build_object('profiles', v_n);

  v_stats := v_stats || jsonb_build_object('user_id', p_user_id, 'ok', true);
  return v_stats;
end;
$$;

comment on function public.staging_nuke_user_data(uuid) is
  'QA/staging ONLY: remove todos os dados públicos do utilizador. '
  'Chamar auth.admin.deleteUser depois. Produção: request_account_deletion (futuro).';

revoke all on function public.staging_nuke_user_data(uuid) from public;
revoke all on function public.staging_nuke_user_data(uuid) from anon;
revoke all on function public.staging_nuke_user_data(uuid) from authenticated;
grant execute on function public.staging_nuke_user_data(uuid) to service_role;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- PRODUÇÃO (futuro — não implementado):
--   1) request_account_deletion → flag profiles.deletion_requested_at
--   2) Bloquear login; anonymizar PII; manter orders/disputas/comissões (obrigação legal)
--   3) auth.admin.deleteUser só após período de graça e zero encomendas activas
--   4) Re-registo: novo auth.users UUID; merge por email só se utilizador confirmar
-- ---------------------------------------------------------------------------
