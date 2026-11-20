create table public.companion_sessions (
 owner_id uuid primary key references public.profiles on delete cascade,
 expires_at timestamptz not null
);
alter table public.companion_sessions enable row level security;
revoke all on public.companion_sessions from public,anon,authenticated;
grant select on public.companion_sessions to authenticated;
create policy read_own_time on public.companion_sessions for select to authenticated using(owner_id=auth.uid());

create function mina_private.open_companion_session() returns timestamptz
language plpgsql security definer set search_path='' as $$
declare expires timestamptz;
begin
 if auth.uid() is null then raise exception 'Sign in to continue.';end if;
 insert into public.companion_sessions(owner_id,expires_at) values(auth.uid(),now()+interval '60 minutes')
 on conflict(owner_id) do update set expires_at=case when public.companion_sessions.expires_at>now() then public.companion_sessions.expires_at else excluded.expires_at end
 returning expires_at into expires;
 return expires;
end $$;
create function public.open_companion_session() returns timestamptz language sql security invoker set search_path=''
as $$select mina_private.open_companion_session()$$;
revoke all on function mina_private.open_companion_session(),public.open_companion_session() from public,anon;
grant execute on function mina_private.open_companion_session(),public.open_companion_session() to authenticated;

create function public.my_level() returns table(contribution bigint,current_level integer,next_threshold bigint)
language sql stable security invoker set search_path='' as $$
 with total as(select coalesce(sum(amount),0)::bigint coins from public.gift_receipts where sender_id=auth.uid()),
 milestones as(select ord-1 as level,threshold from unnest(array[0,100,300,600,1000,2000,3500,5500,8000,12000,20000,35000,60000]::bigint[]) with ordinality as t(threshold,ord))
 select coins,(select max(level)::int from milestones where threshold<=coins),(select min(threshold) from milestones where threshold>coins) from total
$$;
revoke all on function public.my_level() from public,anon;
grant execute on function public.my_level() to authenticated;
