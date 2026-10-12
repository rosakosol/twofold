-- ---------------------------------------------------------------------------
-- Purging an archive early, once nobody is left to keep it for
-- ---------------------------------------------------------------------------
--
-- 20261005000000 made the 90-day timer the only way shared data is ever deleted, and the reason is
-- in 20261003000000: one partner must not be able to destroy the other's copy of a shared history.
-- The timer is the rule that holds for both of them equally.
--
-- That reason runs out when both of them have deleted their accounts. Then there is no copy left
-- that belongs to anybody. The archive cannot be restored (restoring needs both accounts to
-- re-pair) and nobody can read it, so it is just data waiting out a timer that protects nobody. A
-- deleted person asking support "is my data gone?" should get "yes" now, not "in 11 weeks".
--
-- So support can purge early, and only under that condition. Both partners must have
-- `account_deleted_at` set, and the function checks it itself. A console that showed the button
-- only when it was safe would still leave the RPC open to a hand-built call.
--
-- `purge_couple_data` does the work, the same function the timer calls. There is no second
-- implementation of what purging means.
--
-- Recorded once against EACH partner, so the purge shows up in the admin history of whichever
-- account somebody opens later.

create or replace function public.admin_couple_archives(p_profile_id uuid)
returns table (
  couple_id uuid,
  partner_id uuid,
  dissolved_at timestamptz,
  scheduled_purge_at timestamptz,
  self_deleted boolean,
  partner_deleted boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  -- Structure only, like the rest of the account page: when it ended and when it goes, never what
  -- is in it.
  return query
  select c.id,
         case when c.partner_a_id = p_profile_id then c.partner_b_id else c.partner_a_id end,
         c.dissolved_at,
         c.scheduled_purge_at,
         me.account_deleted_at is not null,
         them.account_deleted_at is not null
  from public.couples c
  join public.profiles me on me.id = p_profile_id
  join public.profiles them
    on them.id = case when c.partner_a_id = p_profile_id then c.partner_b_id else c.partner_a_id end
  where (c.partner_a_id = p_profile_id or c.partner_b_id = p_profile_id)
    and c.status = 'dissolved'
  order by c.dissolved_at desc nulls last;
end;
$$;

create or replace function public.admin_purge_couple_archive(p_couple_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_couple public.couples;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;

  select * into v_couple from public.couples where id = p_couple_id for update;
  if not found then
    raise exception 'no such couple';
  end if;
  if v_couple.status <> 'dissolved' then
    raise exception 'only an archived couple can be purged' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.profiles
    where id in (v_couple.partner_a_id, v_couple.partner_b_id)
      and account_deleted_at is null
  ) then
    raise exception 'both partners must have deleted their accounts; otherwise the archive waits for its timer'
      using errcode = '22023';
  end if;

  perform public.purge_couple_data(p_couple_id);

  perform private.record_admin_action(
    'couple.purge', v_couple.partner_a_id, p_reason,
    jsonb_build_object('couple_id', p_couple_id, 'partner_id', v_couple.partner_b_id,
                       'scheduled_purge_at', v_couple.scheduled_purge_at)
  );
  perform private.record_admin_action(
    'couple.purge', v_couple.partner_b_id, p_reason,
    jsonb_build_object('couple_id', p_couple_id, 'partner_id', v_couple.partner_a_id,
                       'scheduled_purge_at', v_couple.scheduled_purge_at)
  );
end;
$$;

revoke all on function public.admin_couple_archives(uuid) from public, anon;
revoke all on function public.admin_purge_couple_archive(uuid, text) from public, anon;
grant execute on function public.admin_couple_archives(uuid) to authenticated;
grant execute on function public.admin_purge_couple_archive(uuid, text) to authenticated;
