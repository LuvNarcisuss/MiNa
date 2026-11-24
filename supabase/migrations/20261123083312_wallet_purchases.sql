create table public.coin_packages (
  product_id text primary key,
  coins integer not null check (coins > 0)
);

insert into public.coin_packages (product_id, coins) values
  ('iukawygoozctrvri', 400),
  ('iuksdwimsbrhwuza', 800),
  ('kbuujljqmlnqmmpp', 2450),
  ('yyzthxzkykuwreyt', 5150),
  ('mxvqqvbrxagzhpzd', 10800),
  ('cbdqrfufpxoocyou', 29400),
  ('ezcsvqkqboqagspr', 63700);

create table public.coin_purchases (
  environment text not null check (environment in ('Sandbox','Production')),
  transaction_id text not null,
  owner_id uuid references public.profiles on delete set null,
  product_id text not null references public.coin_packages,
  coins integer not null check (coins > 0),
  created_at timestamptz not null default now(),
  primary key (environment, transaction_id)
);
create index coin_purchases_history on public.coin_purchases(owner_id, created_at desc);
alter table public.coin_packages enable row level security;
alter table public.coin_purchases enable row level security;
revoke all on public.coin_packages, public.coin_purchases from public, anon, authenticated;
grant select on public.coin_purchases to authenticated;
create policy own_purchases on public.coin_purchases for select to authenticated
  using (owner_id = (select auth.uid()));
grant select on public.coin_packages to service_role;
grant select, insert on public.coin_purchases to service_role;
grant select, update (balance) on public.wallets to service_role;

create view public.sandbox_wallets with (security_invoker = true) as
  select owner_id, sum(coins)::bigint as balance from public.coin_purchases
  where environment = 'Sandbox' and owner_id is not null group by owner_id;
revoke all on public.sandbox_wallets from public, anon, authenticated;
grant select on public.sandbox_wallets to authenticated, service_role;

create function public.credit_coin_purchase(
  account uuid, store_environment text, apple_transaction text, sku text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  newly_credited boolean;
  credits integer;
  current_balance bigint;
  prior public.coin_purchases%rowtype;
begin
  select balance into strict current_balance from public.wallets where owner_id = account for update;
  select coins into strict credits from public.coin_packages where product_id = sku;
  insert into public.coin_purchases(environment, transaction_id, owner_id, product_id, coins)
    values (store_environment, apple_transaction, account, sku, credits)
    on conflict (environment, transaction_id) do nothing;
  newly_credited := found;
  if newly_credited and store_environment = 'Production' then
    update public.wallets set balance = balance + credits where owner_id = account
      returning balance into strict current_balance;
  elsif not newly_credited then
    select * into strict prior from public.coin_purchases
      where environment = store_environment and transaction_id = apple_transaction;
    if prior.owner_id is distinct from account or prior.product_id <> sku then
      raise exception 'Purchase ownership could not be confirmed.';
    end if;
    credits := prior.coins;
  end if;
  if store_environment = 'Sandbox' then
    select balance into strict current_balance from public.sandbox_wallets where owner_id = account;
  end if;
  return jsonb_build_object('environment', store_environment, 'newCredit', newly_credited, 'owner', account, 'product', sku, 'transaction', apple_transaction,
    'coins', credits, 'balance', current_balance);
end $$;
revoke all on function public.credit_coin_purchase(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.credit_coin_purchase(uuid,text,text,text) to service_role;
