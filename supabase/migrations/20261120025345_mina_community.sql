create schema if not exists mina_private;
revoke all on schema mina_private from public;
grant usage on schema mina_private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users on delete cascade default auth.uid(),
  name text not null default 'Night Listener' check (length(name) between 1 and 50),
  avatar_path text not null default '' check (avatar_path='' or split_part(avatar_path,'/',1)=id::text),
  bio text not null default '' check (length(bio)<=500),
  country text not null default '', gender text not null default '', language text not null default '',
  private_profile boolean not null default false, show_status boolean not null default false,
  allow_messages boolean not null default true, allow_calls boolean not null default false
);
create table public.personal_settings (
  id uuid primary key default auth.uid() references auth.users on delete cascade,
  birthday date, accepted_at timestamptz not null default now(), terms_version text not null default '1'
);
create table public.follows (
  follower_id uuid default auth.uid() references public.profiles on delete cascade,
  followed_id uuid references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id,followed_id),check(follower_id<>followed_id)
);
create table public.blocks (
  owner_id uuid default auth.uid() references auth.users on delete cascade,
  blocked_id uuid references auth.users on delete cascade, primary key(owner_id,blocked_id),check(owner_id<>blocked_id)
);
create function mina_private.can_interact(other uuid) returns boolean language sql stable security definer
set search_path='' as $$
 select (select auth.uid()) is not null and not exists(
 select 1 from public.blocks b where (b.owner_id=auth.uid() and b.blocked_id=other) or
 (b.blocked_id=auth.uid() and b.owner_id=other))
$$;
create table public.entries (
  id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid() references public.profiles on delete cascade,
  kind text not null check (kind in ('post','dream')), caption text not null default '' check(length(caption)<=4000),
  media_path text not null check(split_part(media_path,'/',1)=owner_id::text),
  duration real not null default 0 check(duration>=0 and (kind<>'dream' or duration between 0.01 and 60.1)),
  created_at timestamptz not null default now()
);
create table public.entry_comments (
  id uuid primary key default gen_random_uuid(),entry_id uuid not null references public.entries on delete cascade,
  owner_id uuid not null default auth.uid() references public.profiles on delete cascade,
  body text not null check(length(trim(body)) between 1 and 1200), created_at timestamptz not null default now()
);
create table public.entry_reactions (
  entry_id uuid references public.entries on delete cascade, owner_id uuid default auth.uid() references public.profiles on delete cascade,
  kind text not null check(kind in ('like','save')),created_at timestamptz not null default now(), primary key(entry_id,owner_id,kind)
);
create table public.rooms (
  id uuid primary key default gen_random_uuid(),host_id uuid not null default auth.uid() references public.profiles on delete cascade,
  title text not null check(length(trim(title)) between 1 and 20), topic text not null check(length(topic)<=80),cover text not null default 'moon-seat',
  visibility text not null default 'public' check(visibility in ('public','followers','private')),
  allow_follow boolean not null default true,allow_gifts boolean not null default true,allow_comments boolean not null default true,
  closed boolean not null default false,created_at timestamptz not null default now()
);
create table public.room_members (
  room_id uuid references public.rooms on delete cascade,user_id uuid default auth.uid() references public.profiles on delete cascade,
  seat integer check(seat between 0 and 8),joined_at timestamptz not null default now(),last_seen timestamptz not null default now(),
  primary key (room_id,user_id),unique(room_id,seat)
);
create table public.room_messages (
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.rooms on delete cascade,
  owner_id uuid not null default auth.uid() references public.profiles on delete cascade,body text not null check(length(trim(body)) between 1 and 1200),created_at timestamptz not null default now()
);
create table public.room_signals (
  id bigint generated always as identity primary key,room_id uuid not null references public.rooms on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles on delete cascade,recipient_id uuid not null references public.profiles on delete cascade,
  body jsonb not null check(octet_length(body::text)<=65536),created_at timestamptz not null default now()
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),sender_id uuid not null default auth.uid() references public.profiles on delete cascade,
  recipient_id uuid not null references public.profiles on delete cascade,body text not null check(length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),check(sender_id<>recipient_id)
);
create table public.reports (
  id uuid primary key default gen_random_uuid(),reporter_id uuid not null default auth.uid() references auth.users on delete cascade,
  target_id uuid not null,target_kind text not null,reason text not null check(length(trim(reason)) between 1 and 1000),created_at timestamptz not null default now()
);
create index entries_timeline on public.entries(kind,created_at desc);
create index entries_media on public.entries(media_path);
create index comments_entry on public.entry_comments(entry_id);
create index follows_reverse on public.follows(followed_id,follower_id);
create index inbox_recipient on public.messages(recipient_id,created_at desc);
create index inbox_sender on public.messages(sender_id,created_at desc);
create index signals_recipient on public.room_signals(room_id,recipient_id,id);
create index room_chat on public.room_messages(room_id,created_at);
create function mina_private.room_open(r uuid) returns boolean language sql stable security invoker set search_path=''
as $$select exists(select 1 from public.rooms where id=r and not closed)$$;
create function mina_private.member_active(r uuid,u uuid) returns boolean language sql stable security invoker set search_path=''
as $$select exists(select 1 from public.room_members where room_id=r and user_id=u and last_seen>now()-interval '2 minutes')$$;

do $$
declare tab text;
begin
 foreach tab in array array['profiles','personal_settings','follows','blocks','entries','entry_comments','entry_reactions','rooms','room_members','room_messages','room_signals','messages','reports'] loop
 execute format('alter table public.%I enable row level security',tab);
 execute format('revoke all on public.%I from public,anon,authenticated',tab);
 end loop;
end $$;
grant select,insert,update on public.profiles,public.personal_settings to authenticated;
grant select,insert,delete on public.follows,public.blocks,public.entries,public.entry_comments,public.entry_reactions to authenticated;
grant select,insert on public.rooms,public.room_signals,public.room_messages,public.messages,public.reports to authenticated;
grant update(title,topic,visibility,cover,closed,allow_follow,allow_gifts,allow_comments) on public.rooms to authenticated;
grant select,insert,delete on public.room_members to authenticated;
grant update(seat,last_seen) on public.room_members to authenticated;
grant usage,select on sequence public.room_signals_id_seq to authenticated;

create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or (not private_profile and mina_private.can_interact(id)));
create policy profile_create on public.profiles for insert to authenticated with check(id=auth.uid());
create policy profile_edit on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy settings_owner on public.personal_settings for all to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy follow_read on public.follows for select to authenticated using(mina_private.can_interact(follower_id) and mina_private.can_interact(followed_id));
create policy follow_add on public.follows for insert to authenticated with check(follower_id=auth.uid() and mina_private.can_interact(followed_id) and exists(select 1 from public.profiles where id=followed_id));
create policy follow_remove on public.follows for delete to authenticated using(follower_id=auth.uid());
create policy block_owner on public.blocks for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy entry_read on public.entries for select to authenticated using(mina_private.can_interact(owner_id));
create policy entry_add on public.entries for insert to authenticated with check(owner_id=auth.uid());
create policy entry_delete on public.entries for delete to authenticated using(owner_id=auth.uid());
create policy comment_read on public.entry_comments for select to authenticated using(mina_private.can_interact(owner_id) and exists(select 1 from public.entries e where e.id=entry_id));
create policy comment_add on public.entry_comments for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.entries e where e.id=entry_id));
create policy comment_delete on public.entry_comments for delete to authenticated using(owner_id=auth.uid());
create policy reaction_read on public.entry_reactions for select to authenticated using((kind='like' or owner_id=auth.uid()) and mina_private.can_interact(owner_id) and exists(select 1 from public.entries e where e.id=entry_id));
create policy reaction_add on public.entry_reactions for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.entries e where e.id=entry_id));
create policy reaction_delete on public.entry_reactions for delete to authenticated using(owner_id=auth.uid());
create policy room_read on public.rooms for select to authenticated using(host_id=auth.uid() or (mina_private.can_interact(host_id) and (visibility='public' or (visibility='followers' and exists(select 1 from public.follows where followed_id=host_id and follower_id=auth.uid())))));
create policy room_create on public.rooms for insert to authenticated with check(host_id=auth.uid());
create policy room_edit on public.rooms for update to authenticated using(host_id=auth.uid()) with check(host_id=auth.uid());
create policy roster_read on public.room_members for select to authenticated using(mina_private.room_open(room_id) and mina_private.can_interact(user_id));
create policy roster_join on public.room_members for insert to authenticated with check(user_id=auth.uid() and mina_private.room_open(room_id) and (seat is null or exists(select 1 from public.rooms where id=room_id and host_id=auth.uid())));
create policy roster_manage on public.room_members for update to authenticated using((user_id=auth.uid() or exists(select 1 from public.rooms where id=room_id and host_id=auth.uid())) and mina_private.room_open(room_id))
with check(mina_private.room_open(room_id) and (seat is distinct from 0 or exists(select 1 from public.rooms where id=room_id and host_id=user_id)));
create policy roster_leave on public.room_members for delete to authenticated using(user_id=auth.uid() or exists(select 1 from public.rooms where id=room_id and host_id=auth.uid()));
create policy room_chat_read on public.room_messages for select to authenticated using(mina_private.room_open(room_id) and mina_private.can_interact(owner_id));
create policy room_chat_send on public.room_messages for insert to authenticated with check(owner_id=auth.uid() and mina_private.member_active(room_id,auth.uid()) and exists(select 1 from public.rooms where id=room_id and allow_comments and not closed));
create policy signal_read on public.room_signals for select to authenticated using(recipient_id=auth.uid() and mina_private.member_active(room_id,auth.uid()) and mina_private.can_interact(sender_id));
create policy signal_send on public.room_signals for insert to authenticated with check(sender_id=auth.uid() and mina_private.member_active(room_id,auth.uid()) and mina_private.member_active(room_id,recipient_id));
create policy dm_read on public.messages for select to authenticated using(auth.uid() in(sender_id,recipient_id) and mina_private.can_interact(sender_id) and mina_private.can_interact(recipient_id));
create policy dm_send on public.messages for insert to authenticated with check(sender_id=auth.uid() and mina_private.can_interact(recipient_id) and exists(select 1 from public.profiles where id=recipient_id and allow_messages));
create policy report_send on public.reports for insert to authenticated with check(reporter_id=auth.uid());
create policy report_read on public.reports for select to authenticated using(reporter_id=auth.uid());

create function mina_private.guard_seat() returns trigger language plpgsql set search_path='' as $$
begin
 if new.seat is distinct from old.seat and new.seat is not null and not exists(select 1 from public.rooms where id=new.room_id and host_id=auth.uid()) then
 raise exception 'The host admits speakers.'; end if;
 new.last_seen=now(); return new;
end $$;
create trigger guard_seat before update on public.room_members for each row execute function mina_private.guard_seat();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('mina-media','mina-media',false,52428800,array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','audio/mp4','audio/x-m4a','audio/m4a','audio/aac']);
create policy media_add on storage.objects for insert to authenticated with check(bucket_id='mina-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy media_read on storage.objects for select to authenticated using(bucket_id='mina-media' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.entries e where e.media_path=storage.objects.name) or exists(select 1 from public.profiles p where p.avatar_path=storage.objects.name)));
create policy media_delete on storage.objects for delete to authenticated using(bucket_id='mina-media' and (storage.foldername(name))[1]=auth.uid()::text);
alter publication supabase_realtime add table public.messages;
revoke execute on all functions in schema mina_private from public,anon;
grant execute on function mina_private.can_interact(uuid),mina_private.room_open(uuid),mina_private.member_active(uuid,uuid) to authenticated;
