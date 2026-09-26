-- Birthdays, so a couple can be reminded of each other's and the app can mark the day.
--
-- Month and day, deliberately not a full date of birth. A birthday feature needs to know when to
-- celebrate, and nothing here needs to know how old anybody is. A complete DOB is a different
-- class of data — one of the standard identity-verification fields, and the thing that drags an
-- app into age-gating questions it did not previously have. Not collecting the year costs one
-- feature nobody asked for ("turning 30") and avoids all of that.
--
-- Two integers rather than a `date` with the year faked to 2000. A sentinel year is a convention
-- that has to be remembered everywhere the column is read, and the first place it is forgotten it
-- produces somebody born in 2000. Two columns cannot be misread.
--
-- Stored on `profiles`, so each person owns their own. Deliberately not modelled the way
-- `partner_name` is — that one is private, "just for you", and each side keeps an independent
-- value. A birthday is a fact about its owner, and if each partner recorded their guess at the
-- other's there would be two answers and no way to tell which is right, on a feature whose whole
-- job is firing on the correct day.
--
-- No new RLS policy: `profiles_select_self_or_partner` (20260708102734) already lets each partner
-- read the other's row, which is exactly the visibility this needs and no more.

alter table public.profiles
  add column if not exists birthday_month smallint,
  add column if not exists birthday_day smallint;

comment on column public.profiles.birthday_month is
  'Birth month, 1-12. Null together with birthday_day when not provided — it is optional at every '
  'point it is asked for. No year is collected; see 20261110001300.';

comment on column public.profiles.birthday_day is
  'Birth day of month, 1-31, paired with birthday_month.';

-- Ranges only, and no calendar validation beyond them.
--
-- 31 is allowed for every month. Without a year there is no way to reject 31 February that does
-- not also reject 29 February, and somebody born on a leap day has a birthday. A nonsense pair
-- costs a reminder that never fires for a date that does not exist; rejecting leap-day births
-- costs a real person their birthday. The client's picker is what stops the former in practice.
alter table public.profiles
  drop constraint if exists profiles_birthday_range;
alter table public.profiles
  add constraint profiles_birthday_range check (
    (birthday_month is null and birthday_day is null)
    or (
      birthday_month between 1 and 12
      and birthday_day between 1 and 31
    )
  );

-- 20260915000000 revoked table-level UPDATE on profiles and re-granted the columns one at a time,
-- so a new column is unwritable by its owner until it is named here. That migration's comment
-- predicted the trap, 20261106000000 was the first to fall into it and 20261110001200 the second.
-- A missing grant here fails silently: the write returns success and the birthday never saves.
grant update (birthday_month) on public.profiles to anon, authenticated;
grant update (birthday_day) on public.profiles to anon, authenticated;
