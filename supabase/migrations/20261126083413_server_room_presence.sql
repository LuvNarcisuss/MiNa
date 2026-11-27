create view public.online_room_members with (security_invoker = true) as
select room_id, user_id, seat, joined_at, last_seen
from public.room_members
where last_seen > statement_timestamp() - interval '60 seconds';

revoke all on public.online_room_members from public, anon, authenticated;
grant select on public.online_room_members to authenticated;

create function public.room_online_roster(target uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select coalesce(jsonb_agg(to_jsonb(m) order by m.joined_at, m.user_id), '[]'::jsonb)
    from public.online_room_members m
    where m.room_id = target;
$$;

revoke all on function public.room_online_roster(uuid) from public, anon, authenticated;
grant execute on function public.room_online_roster(uuid) to authenticated;

notify pgrst, 'reload schema';
