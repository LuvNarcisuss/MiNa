-- Keep the entry available to its owner's retry until Storage confirms removal.
create table mina_private.entry_media_deletions (
    entry_id uuid primary key references public.entries(id) on delete cascade,
    media_path text not null unique
);
alter table mina_private.entry_media_deletions enable row level security;
revoke all on table mina_private.entry_media_deletions from public, anon, authenticated;
revoke delete on public.entries from authenticated;

-- Serialize new links to an object with the decision to remove its last reference.
create function mina_private.guard_media_reference() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    path text := to_jsonb(new) ->> tg_argv[0];
begin
    if path is null or path = '' then return new; end if;
    if tg_op = 'UPDATE' and (to_jsonb(old) ->> tg_argv[0]) = path then return new; end if;
    perform pg_advisory_xact_lock(hashtextextended(path, 0));
    if exists(select 1 from mina_private.entry_media_deletions d where d.media_path = path) then
        raise exception 'This file is being deleted. Choose another file.';
    end if;
    return new;
end $$;
revoke all on function mina_private.guard_media_reference() from public, anon, authenticated;
create trigger guard_entry_media before insert or update of media_path on public.entries
    for each row execute function mina_private.guard_media_reference('media_path');
create trigger guard_profile_media before insert or update of avatar_path on public.profiles
    for each row execute function mina_private.guard_media_reference('avatar_path');

create function mina_private.prepare_entry_deletion(p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    entry public.entries;
    me uuid := auth.uid();
begin
    if me is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
    select * into entry from public.entries where id = p_id for update;
    if not found then return jsonb_build_object('deleted', true); end if;
    if entry.owner_id <> me or split_part(entry.media_path, '/', 1) <> me::text then
        raise exception 'You can only delete your own entries.' using errcode='42501';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(entry.media_path, 0));
    if exists(select 1 from public.entries e where e.media_path = entry.media_path and e.id <> p_id)
        or exists(select 1 from public.profiles p where p.avatar_path = entry.media_path) then
        delete from public.entries where id = p_id;
        return jsonb_build_object('deleted', true);
    end if;
    insert into mina_private.entry_media_deletions(entry_id, media_path) values (p_id, entry.media_path)
        on conflict (entry_id) do nothing;
    return jsonb_build_object('media_path', entry.media_path);
end $$;

create function mina_private.finish_entry_deletion(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    entry public.entries;
    me uuid := auth.uid();
begin
    if me is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
    select * into entry from public.entries where id = p_id for update;
    if not found then return true; end if;
    if entry.owner_id <> me then raise exception 'You can only delete your own entries.' using errcode='42501'; end if;
    perform pg_advisory_xact_lock(hashtextextended(entry.media_path, 0));
    if not exists(select 1 from mina_private.entry_media_deletions d where d.entry_id = p_id and d.media_path = entry.media_path)
        or exists(select 1 from storage.objects o where o.bucket_id = 'mina-media' and o.name = entry.media_path) then
        raise exception 'Media deletion is incomplete. Please retry.';
    end if;
    delete from public.entries where id = p_id;
    return true;
end $$;

create function public.prepare_entry_deletion(p_id uuid) returns jsonb language sql security invoker set search_path = ''
    as $$ select mina_private.prepare_entry_deletion(p_id) $$;
create function public.finish_entry_deletion(p_id uuid) returns boolean language sql security invoker set search_path = ''
    as $$ select mina_private.finish_entry_deletion(p_id) $$;
revoke all on function mina_private.prepare_entry_deletion(uuid), mina_private.finish_entry_deletion(uuid),
    public.prepare_entry_deletion(uuid), public.finish_entry_deletion(uuid) from public, anon;
grant execute on function mina_private.prepare_entry_deletion(uuid), mina_private.finish_entry_deletion(uuid),
    public.prepare_entry_deletion(uuid), public.finish_entry_deletion(uuid) to authenticated;
