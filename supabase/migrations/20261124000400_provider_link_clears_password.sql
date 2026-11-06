-- A provider signing in to a password account ends the password (security review, F4).
--
-- Email confirmation is off so that sign-up can go straight to a session, in the app and in the web
-- purchase flow. That means a password account proves nothing about who owns its address. Supabase
-- links identities by verified email, so when the real owner later signs in with Google or Apple they
-- land in that same account, and whoever chose the password keeps it, and keeps their sessions.
-- Supabase's own protection does not apply: it removes unconfirmed identities, and with confirmation
-- off this one counts as confirmed. Tested against auth v2.197.0.
--
-- The provider is the first real proof of the address, so what came before it stops counting: the
-- password is cleared and every earlier session ends. The session being signed in is created after
-- this runs, so it survives. An access token already issued can still reach the database until it
-- expires, up to an hour, because a JWT is not checked against auth.sessions there.
--
-- The cost is to somebody who did sign up with their own password and later uses Google or Apple on
-- the same address. Their other devices are signed out, and to use the password again they reset it,
-- which they can do because the address is theirs.
--
-- To turn it off:
--   drop trigger identities_clear_password_on_provider_link on auth.identities;

create or replace function private.clear_password_on_provider_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider in ('email', 'phone') then
    return new;
  end if;

  if exists (
    select 1 from auth.identities i
    where i.user_id = new.user_id and i.provider = 'email' and i.id <> new.id
  ) then
    update auth.users set encrypted_password = null where id = new.user_id;
    delete from auth.sessions where user_id = new.user_id;
  end if;
  return new;
end;
$$;

revoke all on function private.clear_password_on_provider_link() from public, anon, authenticated;

drop trigger if exists identities_clear_password_on_provider_link on auth.identities;
create trigger identities_clear_password_on_provider_link
  after insert on auth.identities
  for each row execute function private.clear_password_on_provider_link();
