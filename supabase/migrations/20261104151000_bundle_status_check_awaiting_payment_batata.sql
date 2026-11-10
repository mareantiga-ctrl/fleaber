-- ZIP149 hotfix: status check + RAISE syntax
alter table public.product_bundles
  drop constraint if exists product_bundles_status_check;
alter table public.product_bundles
  add constraint product_bundles_status_check
  check (
    lower(trim(status)) in (
      'pending','awaiting_payment','accepted','rejected',
      'cancelled','cancelado','expired','purchased'
    )
  );
