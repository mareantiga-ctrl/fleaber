-- BATATA: permitir ver diretos terminados na Home e no player (gravações offline).
-- Sem isto, só o vendedor consegue ler lives com status=ended.

drop policy if exists "lives_select_public_live" on public.lives;

create policy "lives_select_public_live"
  on public.lives
  for select
  using (
    status in ('live', 'ended')
    or is_active = true
    or auth.uid() = seller_id
    or auth.uid() = vendedor_id
  );
