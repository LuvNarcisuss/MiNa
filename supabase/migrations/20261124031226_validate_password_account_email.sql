create or replace function mina_private.validate_account_email() returns trigger
language plpgsql security invoker set search_path = '' as $fn$
begin
    if new.email is null or octet_length(new.email) > 254 or
       octet_length(split_part(new.email, '@', 1)) > 64 or
       new.email !~ $email$^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+([.][A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?([.][A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$$email$ then
        raise exception 'Enter a valid email address.' using errcode = '23514';
    end if;
    return new;
end;
$fn$;
revoke all on function mina_private.validate_account_email() from public, anon, authenticated;
create trigger mina_password_account_email
before insert or update of email, encrypted_password on auth.users
for each row when (coalesce(new.encrypted_password, '') <> '')
execute function mina_private.validate_account_email();
