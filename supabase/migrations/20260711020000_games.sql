-- Couple Games: a reusable session system (not four disconnected implementations) shared by
-- Travel Trivia Battle, Who's More Likely To, This or That, and Discuss Before Travelling.
--
-- Security model: a partner's answer must be unreadable via a raw client query (not just
-- hidden in the UI) until both partners have answered the same round. See the select policy
-- on game_responses below for the mechanism — no separate "presence" table is needed; waiting
-- state is derived purely from how many rows are visible to the caller.

create type public.game_type as enum ('travel_trivia', 'more_likely', 'this_or_that', 'discuss_before_travelling');
create type public.game_status as enum ('draft', 'active', 'waiting_for_partner', 'completed', 'abandoned');

-- ---------------------------------------------------------------------------
-- Content tables: shared seed data, not couple-scoped. Readable by any
-- authenticated user; writable only via migrations/service role (no client
-- insert/update/delete grants).
-- ---------------------------------------------------------------------------

create table public.trivia_questions (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  question text not null,
  options jsonb not null,
  correct_answer text not null,
  explanation text,
  difficulty text,
  active boolean not null default true
);

create table public.more_likely_prompts (
  id uuid primary key default gen_random_uuid(),
  prompt text not null,
  active boolean not null default true
);

create table public.this_or_that_prompts (
  id uuid primary key default gen_random_uuid(),
  option_a text not null,
  option_b text not null,
  active boolean not null default true
);

create table public.discussion_topics (
  id uuid primary key default gen_random_uuid(),
  topic text not null,
  active boolean not null default true
);

alter table public.trivia_questions enable row level security;
alter table public.more_likely_prompts enable row level security;
alter table public.this_or_that_prompts enable row level security;
alter table public.discussion_topics enable row level security;

create policy "trivia_questions_select_authenticated" on public.trivia_questions for select to authenticated using (true);
create policy "more_likely_prompts_select_authenticated" on public.more_likely_prompts for select to authenticated using (true);
create policy "this_or_that_prompts_select_authenticated" on public.this_or_that_prompts for select to authenticated using (true);
create policy "discussion_topics_select_authenticated" on public.discussion_topics for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Session tables
-- ---------------------------------------------------------------------------

-- Participants are never stored separately — a Twofold game is always exactly the couple's
-- two members, derived from couples.partner_a_id/partner_b_id via couple_id.
create table public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete cascade,
  game_type public.game_type not null,
  initiator_id uuid not null references public.profiles (id),
  status public.game_status not null default 'active',
  current_round int not null default 1,
  total_rounds int not null default 5,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index game_sessions_couple_id_idx on public.game_sessions (couple_id);

-- content_id is deliberately not a foreign key: which table it points into depends on the
-- session's game_type (polymorphic), resolved client-side the same way the rest of this app
-- composes multi-table reads in Swift rather than via SQL joins/views.
create table public.game_session_rounds (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.game_sessions (id) on delete cascade,
  round_number int not null,
  content_id uuid not null,
  discussion_status text,
  unique (session_id, round_number)
);

create table public.game_responses (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.game_sessions (id) on delete cascade,
  round_number int not null,
  responder_id uuid not null references public.profiles (id),
  answer jsonb not null,
  is_correct boolean,
  created_at timestamptz not null default now(),
  unique (session_id, round_number, responder_id)
);

create index game_responses_session_round_idx on public.game_responses (session_id, round_number);

alter table public.game_sessions enable row level security;
alter table public.game_session_rounds enable row level security;
alter table public.game_responses enable row level security;

-- No client UPDATE policy on game_sessions/game_session_rounds anywhere below — every state
-- transition goes through a security definer RPC or trigger, never a direct client .update().

create policy "game_sessions_select_members" on public.game_sessions
  for select using (public.is_couple_member(couple_id));

create policy "game_session_rounds_select_members" on public.game_session_rounds
  for select using (
    exists (
      select 1 from public.game_sessions gs
      where gs.id = game_session_rounds.session_id and public.is_couple_member(gs.couple_id)
    )
  );

-- The reveal mechanism: your own row is always visible. Your partner's row for the same
-- round only becomes visible once a *different* responder's row also exists for that round —
-- since a couple has exactly two members and (session_id, round_number, responder_id) is
-- unique, "a different responder answered" can only mean both partners have now answered.
-- No UPDATE or DELETE policy exists on this table at all: answers are immutable once
-- submitted, so nobody can retroactively edit their answer after seeing the reveal.
create policy "game_responses_select_own_or_revealed" on public.game_responses
  for select using (
    responder_id = auth.uid()
    or (
      exists (
        select 1 from public.game_sessions gs
        where gs.id = game_responses.session_id and public.is_couple_member(gs.couple_id)
      )
      and exists (
        select 1 from public.game_responses gr2
        where gr2.session_id = game_responses.session_id
          and gr2.round_number = game_responses.round_number
          and gr2.responder_id <> game_responses.responder_id
      )
    )
  );

create policy "game_responses_insert_own_active" on public.game_responses
  for insert with check (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and public.is_couple_member(gs.couple_id)
        and public.is_couple_active(gs.couple_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Trigger: advances the session's round/status whenever a response comes in.
-- security definer so its internal count query isn't itself subject to the
-- inserting user's own game_responses RLS. Atomic increment (not read-then-write
-- from a variable) to avoid lost-update races between near-simultaneous answers.
-- ---------------------------------------------------------------------------

create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_answered_count int;
  v_total_rounds int;
begin
  select count(distinct responder_id) into v_answered_count
  from public.game_responses
  where session_id = new.session_id and round_number = new.round_number;

  select total_rounds into v_total_rounds
  from public.game_sessions where id = new.session_id;

  update public.game_sessions
  set started_at = coalesce(started_at, now()),
      updated_at = now(),
      status = case
        when v_answered_count >= 2 and new.round_number >= v_total_rounds then 'completed'
        when v_answered_count >= 2 then 'active'
        else 'waiting_for_partner'
      end::public.game_status,
      current_round = case
        when v_answered_count >= 2 and new.round_number < v_total_rounds then new.round_number + 1
        else current_round
      end,
      completed_at = case
        when v_answered_count >= 2 and new.round_number >= v_total_rounds then now()
        else completed_at
      end
  where id = new.session_id;

  return new;
end;
$$;

create trigger game_responses_advance_session
  after insert on public.game_responses
  for each row execute function public.advance_game_session();

-- ---------------------------------------------------------------------------
-- RPCs: the only sanctioned way to start or abandon a session, or mark a
-- discussion round's status — mirrors create_invite_code/redeem_invite_code.
-- ---------------------------------------------------------------------------

create or replace function public.start_game_session(p_game_type public.game_type)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_session_id uuid;
  v_content_ids uuid[];
  v_round_count int := 5;
  i int;
begin
  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  if v_couple_id is null then
    raise exception 'No active couple for the current user';
  end if;

  case p_game_type
    when 'travel_trivia' then
      select array_agg(id) into v_content_ids from (
        select id from public.trivia_questions where active order by random() limit v_round_count
      ) t;
    when 'more_likely' then
      select array_agg(id) into v_content_ids from (
        select id from public.more_likely_prompts where active order by random() limit v_round_count
      ) t;
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from (
        select id from public.this_or_that_prompts where active order by random() limit v_round_count
      ) t;
    when 'discuss_before_travelling' then
      select array_agg(id) into v_content_ids from (
        select id from public.discussion_topics where active order by random() limit v_round_count
      ) t;
  end case;

  if v_content_ids is null or array_length(v_content_ids, 1) < v_round_count then
    raise exception 'Not enough active content to start this game';
  end if;

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds)
  values (v_couple_id, p_game_type, auth.uid(), 'active', v_round_count)
  returning id into v_session_id;

  for i in 1..v_round_count loop
    insert into public.game_session_rounds (session_id, round_number, content_id)
    values (v_session_id, i, v_content_ids[i]);
  end loop;

  return v_session_id;
end;
$$;

create or replace function public.abandon_game_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.game_sessions
  set status = 'abandoned', updated_at = now()
  where id = p_session_id and public.is_couple_member(couple_id);
end;
$$;

create or replace function public.mark_discussion_round(p_round_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('talked_about', 'come_back_later') then
    raise exception 'Invalid discussion status: %', p_status;
  end if;

  update public.game_session_rounds gsr
  set discussion_status = p_status
  from public.game_sessions gs
  where gsr.id = p_round_id
    and gs.id = gsr.session_id
    and public.is_couple_member(gs.couple_id);
end;
$$;

revoke all on function public.start_game_session(public.game_type) from public;
grant execute on function public.start_game_session(public.game_type) to authenticated;

revoke all on function public.abandon_game_session(uuid) from public;
grant execute on function public.abandon_game_session(uuid) to authenticated;

revoke all on function public.mark_discussion_round(uuid, text) from public;
grant execute on function public.mark_discussion_round(uuid, text) to authenticated;

-- Required for postgres_changes Realtime subscriptions to fire on these tables.
alter publication supabase_realtime add table public.game_sessions;
alter publication supabase_realtime add table public.game_responses;
