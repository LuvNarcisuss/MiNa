-- Preserve historical purchases for reconciliation while retiring remote checkout.
drop function if exists public.credit_coin_purchase(uuid, text, text, text);
revoke insert, update, delete, truncate on public.coin_purchases from service_role;
notify pgrst, 'reload schema';
