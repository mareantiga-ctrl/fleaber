-- P2 lote 3: G-P2-04 / RTB-B-1755-P2-RAFFLE-WINNERS
-- BUG: qualquer auth lia live_raffle_winners (user_id + draw_proof.seed) de rifas drawn.
-- Preserva: UI via batata_get_live_raffle_state (sem draw_proof); seller vê winners da sua rifa;
--           vencedor vê a própria row (incl. proof se precisar).
-- production_touched: false · fase4: false

drop policy if exists live_raffle_winners_select_auth on public.live_raffle_winners;
create policy live_raffle_winners_select_auth
  on public.live_raffle_winners
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.live_raffles r
      join public.lives l on l.id = r.live_id
      where r.id = live_raffle_winners.raffle_id
        and coalesce(l.seller_id, l.vendedor_id, r.seller_id) = auth.uid()
    )
    or public.batata_is_admin()
  );

comment on policy live_raffle_winners_select_auth on public.live_raffle_winners is
  'P2-RAFFLE-WINNERS: só vencedor, seller da live, ou admin — sem enum global de draw_proof.';

notify pgrst, 'reload schema';
