-- ============================================================
-- 18+ questions, only when both partners have chosen them
-- ============================================================
--
-- Some couples want questions about sex and intimacy, and the catalogue had none. They belong
-- behind a gate that two people have to open, not one: a question about desire put in front of a
-- partner who did not ask for it is the problem, not the solution.
--
-- So each partner opts in for themselves, and that opt-in is also their statement that they are 18
-- or over. Twofold does not store anyone's age (birthdays are day and month only, and the privacy
-- policy promises nothing that reveals it), so the opt-in is the age check, and it has to come from
-- both of them. Until both have opted in, 18+ decks do not exist as far as the couple can tell: not
-- locked, not teased, absent. Their titles are not for a screen somebody glances at.
--
-- One partner turning it off closes it for both, immediately, for the same reason.
--
-- ---------------------------------------------------------------------------
-- Where the gate is
-- ---------------------------------------------------------------------------
--
--   * The read policies on game_decks and the four content tables, so neither the app nor a REST
--     client can see an 18+ deck or question until both have opted in. Admins still see everything
--     through their `*_admin_write` policies, which cover select.
--   * start_deck_session, which is a definer and bypasses those policies. It is the only function
--     left that picks content: start_game_session, which picked from every deck at random, was
--     dropped in 20260809000000.
--
-- The opt-in column is written only by set_adult_content_opt_in. Profiles are updatable column by
-- column (20260915000000), so a new column is already out of the client's reach; the revoke below
-- says so where the column is created.

alter table public.profiles add column if not exists adult_content_opt_in_at timestamptz;
revoke update (adult_content_opt_in_at) on public.profiles from anon, authenticated;

alter table public.game_decks add column if not exists adult boolean not null default false;

-- ---------------------------------------------------------------------------
-- Whether the caller's couple has both opted in
-- ---------------------------------------------------------------------------
-- A definer so the couple and partner lookups are not themselves filtered by RLS. False for anyone
-- without an active couple: one person cannot open this alone.

create or replace function private.viewer_adult_unlocked()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.couples c
    join public.profiles me on me.id = auth.uid()
    join public.profiles partner
      on partner.id = case when c.partner_a_id = auth.uid() then c.partner_b_id else c.partner_a_id end
    where (c.partner_a_id = auth.uid() or c.partner_b_id = auth.uid())
      and c.status = 'active'
      and me.adult_content_opt_in_at is not null
      and partner.adult_content_opt_in_at is not null
      and partner.account_deleted_at is null
  );
$$;

-- Which decks are 18+, read past game_decks' own policy. A policy on a content table cannot ask
-- game_decks directly: that policy hides 18+ decks, so "is this row's deck 18+?" would come back
-- "no such deck" and let the row through.
create or replace function private.adult_deck_ids()
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(id), '{}') from public.game_decks where adult;
$$;

-- ---------------------------------------------------------------------------
-- The read policies
-- ---------------------------------------------------------------------------
-- `(select ...)` so each function runs once per query rather than once per row.

drop policy if exists "game_decks_select_authenticated" on public.game_decks;
create policy "game_decks_select_authenticated" on public.game_decks
  for select to authenticated
  using (not adult or (select private.viewer_adult_unlocked()));

drop policy if exists "trivia_questions_select_authenticated" on public.trivia_questions;
create policy "trivia_questions_select_authenticated" on public.trivia_questions
  for select to authenticated
  using (
    (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium')
    and (deck_id is null or deck_id <> all ((select private.adult_deck_ids())::uuid[]) or (select private.viewer_adult_unlocked()))
  );

drop policy if exists "more_likely_prompts_select_authenticated" on public.more_likely_prompts;
create policy "more_likely_prompts_select_authenticated" on public.more_likely_prompts
  for select to authenticated
  using (
    (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium')
    and (deck_id is null or deck_id <> all ((select private.adult_deck_ids())::uuid[]) or (select private.viewer_adult_unlocked()))
  );

drop policy if exists "this_or_that_prompts_select_authenticated" on public.this_or_that_prompts;
create policy "this_or_that_prompts_select_authenticated" on public.this_or_that_prompts
  for select to authenticated
  using (
    (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium')
    and (deck_id is null or deck_id <> all ((select private.adult_deck_ids())::uuid[]) or (select private.viewer_adult_unlocked()))
  );

drop policy if exists "deep_conversation_topics_select_authenticated" on public.deep_conversation_topics;
create policy "deep_conversation_topics_select_authenticated" on public.deep_conversation_topics
  for select to authenticated
  using (
    (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium')
    and (deck_id is null or deck_id <> all ((select private.adult_deck_ids())::uuid[]) or (select private.viewer_adult_unlocked()))
  );

-- ---------------------------------------------------------------------------
-- Opting in and out, and seeing where the other partner stands
-- ---------------------------------------------------------------------------

create or replace function public.set_adult_content_opt_in(p_on boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  update public.profiles
  set adult_content_opt_in_at = case when p_on then coalesce(adult_content_opt_in_at, now()) else null end
  where id = auth.uid();
end;
$$;

-- Only whether the partner has opted in, never when: the time is theirs.
create or replace function public.adult_content_status()
returns table (me boolean, partner boolean, has_partner boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select adult_content_opt_in_at is not null from public.profiles where id = auth.uid()),
    coalesce((
      select p.adult_content_opt_in_at is not null and p.account_deleted_at is null
      from public.couples c
      join public.profiles p
        on p.id = case when c.partner_a_id = auth.uid() then c.partner_b_id else c.partner_a_id end
      where (c.partner_a_id = auth.uid() or c.partner_b_id = auth.uid()) and c.status = 'active'
      limit 1
    ), false),
    exists (
      select 1 from public.couples c
      where (c.partner_a_id = auth.uid() or c.partner_b_id = auth.uid()) and c.status = 'active'
    );
$$;

revoke all on function public.set_adult_content_opt_in(boolean) from public, anon;
revoke all on function public.adult_content_status() from public, anon;
grant execute on function public.set_adult_content_opt_in(boolean) to authenticated;
grant execute on function public.adult_content_status() to authenticated;

-- ---------------------------------------------------------------------------
-- The definer that picks content
-- ---------------------------------------------------------------------------

create or replace function public.start_deck_session(p_deck_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_session_id uuid;
  v_deck record;
  v_content_ids uuid[];
  v_round_count int;
  v_effective_tier text;
  i int;
begin
  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  select * into v_deck from public.game_decks where id = p_deck_id and active;
  if v_deck is null then
    raise exception 'Deck not found';
  end if;

  if v_couple_id is null and v_deck.game_type = 'more_likely' then
    raise exception 'This game needs a partner';
  end if;

  v_effective_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    else coalesce((select subscription_tier from public.profiles where id = auth.uid()), 'plus')
  end;

  if v_deck.tier = 'premium' and v_effective_tier <> 'premium' then
    raise exception 'This deck requires Premium';
  end if;

  -- 18+ decks need both partners to have opted in (see the header). Checked here as well as in the
  -- read policies because this function is a definer and would otherwise build the session anyway.
  if v_deck.adult and not private.viewer_adult_unlocked() then
    raise exception 'This deck needs both partners to turn on 18+ questions';
  end if;

  -- The resume. Newest first, because the duplicates this migration stops creating already exist
  -- in production and the most recent one is the one a player was last looking at.
  select id into v_session_id
  from public.game_sessions
  where deck_id = p_deck_id
    and status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and couple_id = v_couple_id)
      or (v_couple_id is null and couple_id is null and initiator_id = auth.uid())
    )
  order by created_at desc
  limit 1;

  if v_session_id is not null then
    return v_session_id;
  end if;

  -- Only cards the couple can read. The content policies hide a premium card from anyone below
  -- premium (20260922000000); a round built on one is a round the app has no card for, and it
  -- showed "you've finished" in its place.
  case v_deck.game_type
    when 'trivia_battle' then
      select array_agg(id) into v_content_ids from public.trivia_questions
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
    when 'more_likely' then
      select array_agg(id) into v_content_ids from public.more_likely_prompts
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from public.this_or_that_prompts
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
    when 'deep_conversations' then
      select array_agg(id) into v_content_ids from public.deep_conversation_topics
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
  end case;

  if v_content_ids is null or array_length(v_content_ids, 1) = 0 then
    raise exception 'This deck has no content';
  end if;

  v_round_count := array_length(v_content_ids, 1);

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, deck_id)
  values (v_couple_id, v_deck.game_type, auth.uid(), 'active', v_round_count, p_deck_id)
  returning id into v_session_id;

  for i in 1..v_round_count loop
    insert into public.game_session_rounds (session_id, round_number, content_id)
    values (v_session_id, i, v_content_ids[i]);
  end loop;

  return v_session_id;
end;
$$;
