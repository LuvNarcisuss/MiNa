create function public.bootstrap() returns uuid language plpgsql security invoker set search_path='' as $$
declare account uuid := auth.uid();
begin
 if account is null then raise exception 'Sign in to continue.'; end if;
 insert into public.profiles(id) values(account) on conflict(id) do nothing;
 insert into public.personal_settings(id) values(account) on conflict(id) do nothing;
 return account;
end $$;
revoke execute on function public.bootstrap() from public,anon;
grant execute on function public.bootstrap() to authenticated;
