create or replace function mina_private.guard_media_reference() returns trigger
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
    if not exists(select 1 from storage.objects o where o.bucket_id = 'mina-media' and o.name = path) then
        raise exception 'Upload the media before publishing.' using errcode = '23514';
    end if;
    return new;
end $$;
revoke all on function mina_private.guard_media_reference() from public, anon, authenticated;
