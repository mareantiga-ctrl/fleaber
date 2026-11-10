-- PS ingest audit — uma linha por CADA tentativa de ingest (não colapsa com supersede).
-- Deploy staging: aplicar este SQL + redeploy edge ingest-ocr-reservation.
-- Depois: node tool/ps_ai/dump_ingest_audit.mjs --live-id <UUID>

create table if not exists public.ps_ingest_audit (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.lives (id) on delete cascade,
  seller_id uuid references public.profiles (id) on delete set null,
  chat_sequence int,
  ocr_line_hash text,
  ocr_raw_line text,
  external_display_name text,
  external_buyer_ref text,
  parser_intent text,
  requested_qty int,
  ref_slug_in text,
  public_slot_in int,
  -- resultado do RPC / edge
  ok boolean,
  action text,
  reservation_id uuid,
  resolved_ref_slug text,
  qty_after int,
  ingest_status text,
  error text,
  result_meta jsonb,
  device_id text,
  created_at timestamptz not null default now()
);

create index if not exists ps_ingest_audit_live_seq_idx
  on public.ps_ingest_audit (live_id, chat_sequence asc nulls last, created_at asc);

create index if not exists ps_ingest_audit_live_created_idx
  on public.ps_ingest_audit (live_id, created_at asc);

alter table public.ps_ingest_audit enable row level security;

drop policy if exists ps_ingest_audit_seller_select on public.ps_ingest_audit;
create policy ps_ingest_audit_seller_select
  on public.ps_ingest_audit
  for select
  to authenticated
  using (
    seller_id = auth.uid()
    or exists (
      select 1 from public.lives l
      where l.id = live_id
        and coalesce(l.seller_id, l.vendedor_id) = auth.uid()
    )
  );

-- Inserção só via service_role (edge). Sem grant a authenticated para insert.
revoke all on table public.ps_ingest_audit from public;
grant select on table public.ps_ingest_audit to authenticated;
grant all on table public.ps_ingest_audit to service_role;

comment on table public.ps_ingest_audit is
  'Append-only: cada comentário PS/OCR ingerido. live_reservation_requests continua a colapsar supersede; esta tabela guarda o passo a passo.';
