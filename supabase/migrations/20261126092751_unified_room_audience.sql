create view public.room_audience_members with (security_invoker = true) as
select live.room_id, live.user_id, live.seat, live.joined_at, live.last_seen, true as connected
from public.online_room_members live
union all
select assigned.room_id, assigned.user_id, null, null, null, false
from public.room_regulars assigned
where not exists (
    select 1 from public.online_room_members live
    where live.room_id = assigned.room_id and live.user_id = assigned.user_id
);

revoke all on public.room_audience_members from public, anon, authenticated;
grant select on public.room_audience_members to authenticated;

create function public.room_audience_count(public.rooms) returns bigint
language sql stable security invoker set search_path = '' as $$
    select count(*) from public.room_audience_members m where m.room_id = $1.id;
$$;

create function public.room_audience_roster(target uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select coalesce(jsonb_agg(to_jsonb(m) order by m.joined_at nulls last, m.user_id), '[]'::jsonb)
    from public.room_audience_members m where m.room_id = target;
$$;

revoke all on function public.room_audience_count(public.rooms), public.room_audience_roster(uuid)
    from public, anon, authenticated;
grant execute on function public.room_audience_count(public.rooms), public.room_audience_roster(uuid)
    to authenticated;

notify pgrst, 'reload schema';
