create table public.support_requests (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users on delete cascade,
 body text not null check(length(trim(body)) between 5 and 2000),
 created_at timestamptz not null default now()
);
alter table public.support_requests enable row level security;
revoke all on public.support_requests from public,anon,authenticated;
grant insert,select on public.support_requests to authenticated;
create policy support_owner_read on public.support_requests for select to authenticated using(owner_id=auth.uid());
create policy support_owner_send on public.support_requests for insert to authenticated with check(owner_id=auth.uid());
