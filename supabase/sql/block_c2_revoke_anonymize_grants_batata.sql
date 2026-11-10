-- Harden grants: anonymize only service_role.
revoke all on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) from public;
revoke all on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) from anon;
revoke all on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) from authenticated;
grant execute on function public.batata_anonymize_account_for_deletion(uuid, text, text, text, boolean) to service_role;

notify pgrst, 'reload schema';
