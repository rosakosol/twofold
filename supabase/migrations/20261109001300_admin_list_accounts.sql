-- ---------------------------------------------------------------------------
-- Browsing accounts, newest first
-- ---------------------------------------------------------------------------
--
-- `admin_lookup_account` answers "find the person who emailed". This answers "who has signed up",
-- which is a different question and the one a console is asked when nobody has written in — how
-- many people are there, who arrived this week, did that account ever finish onboarding.
--
-- Paginated rather than capped, and ordered by `created_at desc` because the recent end is the one
-- anybody looks at.
--
-- ---------------------------------------------------------------------------
-- What it returns, and what still costs an audit row
-- ---------------------------------------------------------------------------
--
-- The same nine columns the search returns: enough to recognise a row and decide whether to open
-- it, and nothing more. No partner, no history, no subscription detail, no content of any kind.
--
-- Reading this list is not audited, for the same reason searching is not: it says who exists, not
-- who anybody is. `admin_account_detail` remains the audited call, because that is still the one
-- that turns a row into a person — and it is unchanged by this.
--
-- `total_count` rides along on every row rather than needing a second call. It is a window
-- function over the same scan, so the count and the page can never disagree about what they are
-- counting, which they can when a separate `select count(*)` runs a moment later.

create or replace function public.admin_list_accounts(
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  profile_id uuid,
  email text,
  first_name text,
  created_at timestamptz,
  last_active_at timestamptz,
  subscription_tier text,
  subscription_active boolean,
  has_partner boolean,
  deleted_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    select
      p.id,
      u.email::text,
      p.first_name,
      p.created_at,
      p.last_active_at,
      p.subscription_tier,
      p.subscription_active,
      exists (
        select 1 from public.couples c
        where c.status = 'active' and (c.partner_a_id = p.id or c.partner_b_id = p.id)
      ),
      -- A deleted account still appears, and says so. `delete_own_account` soft-deletes: the
      -- auth.users row survives so the FK cascade never takes the other partner's shared history
      -- with it, which means "gone" and "absent from this list" are not the same thing.
      u.deleted_at,
      count(*) over ()
    from public.profiles p
    join auth.users u on u.id = p.id
    order by p.created_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke execute on function public.admin_list_accounts(integer, integer) from anon;
grant execute on function public.admin_list_accounts(integer, integer) to authenticated;
