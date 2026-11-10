-- SEC-039 — restringir SELECT aberto em rifas / winners / referral codes (BATATA)
-- App: studio + player fazem stream/select em live_raffles por live_id.
-- Referral codes: só via RPC hoje — SELECT directo já não precisa de using(true).
-- Não toca RPCs de criar/sortear/partilhar.

-- 1) live_raffles: dono da live OU rifa pública (active/closed/drawn)
drop policy if exists live_raffles_select_auth on public.live_raffles;
create policy live_raffles_select_auth
  on public.live_raffles for select to authenticated
  using (
    lower(coalesce(status, '')) in ('active', 'closed', 'drawn')
    or exists (
      select 1
      from public.lives l
      where l.id = live_raffles.live_id
        and coalesce(l.seller_id, l.vendedor_id) = auth.uid()
    )
    or public.batata_is_admin()
  );

-- 2) winners: alinhado à rifa visível
drop policy if exists live_raffle_winners_select_auth on public.live_raffle_winners;
create policy live_raffle_winners_select_auth
  on public.live_raffle_winners for select to authenticated
  using (
    exists (
      select 1
      from public.live_raffles r
      where r.id = live_raffle_winners.raffle_id
        and (
          lower(coalesce(r.status, '')) in ('active', 'closed', 'drawn')
          or exists (
            select 1
            from public.lives l
            where l.id = r.live_id
              and coalesce(l.seller_id, l.vendedor_id) = auth.uid()
          )
        )
    )
    or public.batata_is_admin()
  );

-- 3) referral_links: código sensível — só dono do link, seller da live, ou admin
drop policy if exists live_raffle_referral_links_select_auth on public.live_raffle_referral_links;
create policy live_raffle_referral_links_select_auth
  on public.live_raffle_referral_links for select to authenticated
  using (
    referrer_user_id = auth.uid()
    or exists (
      select 1
      from public.lives l
      where l.id = live_raffle_referral_links.live_id
        and coalesce(l.seller_id, l.vendedor_id) = auth.uid()
    )
    or public.batata_is_admin()
  );

notify pgrst, 'reload schema';
