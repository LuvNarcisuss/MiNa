create table public.room_regulars (
    room_id uuid not null references public.rooms(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    primary key (room_id, user_id)
);

create index room_regulars_user_id_idx on public.room_regulars(user_id);
alter table public.room_regulars enable row level security;
revoke all on public.room_regulars from public, anon, authenticated;
grant select on public.room_regulars to authenticated;
grant all on public.room_regulars to service_role;

create policy read_visible_room_regulars on public.room_regulars
    for select to authenticated using (
        exists (select 1 from public.rooms r where r.id = room_regulars.room_id and not r.closed)
        and exists (select 1 from public.profiles p where p.id = room_regulars.user_id)
    );

notify pgrst, 'reload schema';
