create or replace function mina_private.open_companion_session() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
    account uuid := auth.uid();
    expires timestamptz;
begin
    -- A signed access token can outlive its account. Lock the live parent through the write.
    perform 1 from auth.users where id = account and deleted_at is null for share;
    if not found then
        raise exception using errcode = 'PT401', message = 'Your session has expired. Please sign in again.';
    end if;
    perform public.bootstrap();
    insert into public.companion_sessions(owner_id, expires_at)
    values (account, now() + interval '60 minutes')
    on conflict (owner_id) do update
       set expires_at = case when public.companion_sessions.expires_at > now()
                then public.companion_sessions.expires_at else excluded.expires_at end
    returning expires_at into expires;
    return expires;
end $$;
