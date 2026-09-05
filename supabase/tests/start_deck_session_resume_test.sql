-- ---------------------------------------------------------------------------
-- start_deck_session: one open session per deck, not one per call
-- ---------------------------------------------------------------------------
--
-- The RPC used to insert unconditionally: a session row plus one round row per question, on every
-- call, callable directly by any authenticated client with no rate limit. Looped it wrote unbounded
-- rows, and for an ordinary user it split a couple's progress across two rows that each showed
-- partial answers.
--
-- The assertions that matter come in pairs. Resuming must be narrow enough that a FINISHED deck can
-- be replayed — people do replay them, and a replay must get its own row rather than reopening the
-- old one and destroying the record of the first play. And it must not become a way around the
-- refusals: the tier gate and the partner rule are checked before the resume, so a lapsed
-- subscriber cannot pick a premium deck back up.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1111-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@resume.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1111-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@resume.test', 'x', now(), now(), now()),
  ('cccccccc-1111-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@resume.test', 'x', now(), now(), now());

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('dddddddd-1111-0000-0000-000000000004',
        'aaaaaaaa-1111-0000-0000-000000000001',
        'bbbbbbbb-1111-0000-0000-000000000002',
        'active');

-- Two real plus decks of the same game type, so "a different deck gets its own session" is a
-- genuine comparison rather than a comparison against a type the RPC handles down another branch.
--
-- Held in transaction-local settings rather than a temp table: a temp table is owned by postgres,
-- and these tests spend most of their time as `authenticated`, which cannot read it.
select set_config('test.deck1', (
  select id::text from public.game_decks
  where tier = 'plus' and active and game_type = 'deep_conversations' and question_count > 0
  order by id limit 1
), true);
select set_config('test.deck2', (
  select id::text from public.game_decks
  where tier = 'plus' and active and game_type = 'deep_conversations' and question_count > 0
  order by id offset 1 limit 1
), true);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-000000000001","role":"authenticated"}';

-- ---------------------------------------------------------------------------
-- The core property
-- ---------------------------------------------------------------------------

select set_config('test.first_session',
  public.start_deck_session(current_setting('test.deck1')::uuid)::text, true);

select is(
  public.start_deck_session(current_setting('test.deck1')::uuid),
  current_setting('test.first_session')::uuid,
  'calling twice for the same deck returns the same session'
);

select is(
  (select count(*)::int from public.game_sessions
    where deck_id = current_setting('test.deck1')::uuid
      and couple_id = 'dddddddd-1111-0000-0000-000000000004'),
  1,
  'and only one session row was written'
);

-- The partner resumes the same session, not their own parallel one — the row is the couple's.
set local request.jwt.claims = '{"sub":"bbbbbbbb-1111-0000-0000-000000000002","role":"authenticated"}';
select is(
  public.start_deck_session(current_setting('test.deck1')::uuid),
  current_setting('test.first_session')::uuid,
  'the partner resumes the couple''s session rather than starting a second'
);

-- A different deck is a different session.
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-000000000001","role":"authenticated"}';
select isnt(
  public.start_deck_session(current_setting('test.deck2')::uuid),
  current_setting('test.first_session')::uuid,
  'a different deck still gets its own session'
);

-- ---------------------------------------------------------------------------
-- What must NOT be resumed
-- ---------------------------------------------------------------------------

reset role;
update public.game_sessions set status = 'completed'
  where deck_id = current_setting('test.deck1')::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-000000000001","role":"authenticated"}';

select isnt(
  public.start_deck_session(current_setting('test.deck1')::uuid),
  current_setting('test.first_session')::uuid,
  'a completed deck starts a fresh session — a replay must not reopen the finished one'
);

reset role;
update public.game_sessions set status = 'abandoned'
  where deck_id = current_setting('test.deck1')::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from public.game_sessions
    where deck_id = current_setting('test.deck1')::uuid
      and status in ('active', 'waiting_for_partner')),
  0,
  'with every session abandoned, none is resumable'
);

-- The call itself, which test 7 then measures. Without it that assertion counts rows nobody
-- created and passes or fails on the fixtures rather than on the behaviour.
select set_config('test.after_abandon',
  public.start_deck_session(current_setting('test.deck1')::uuid)::text, true);

select is(
  (select count(*)::int from public.game_sessions
    where deck_id = current_setting('test.deck1')::uuid
      and status in ('active', 'waiting_for_partner')),
  1,
  'so another call adds a new open session rather than reviving an abandoned one'
);

-- ---------------------------------------------------------------------------
-- The resume is not a way around the refusals
-- ---------------------------------------------------------------------------
--
-- The checks run before the resume lookup, so this holds even though the solo user has no session
-- to resume — it is the ordering that is being pinned, not the absence of a row.

set local request.jwt.claims = '{"sub":"cccccccc-1111-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  format($$select public.start_deck_session(%L)$$,
    (select id from public.game_decks where game_type = 'more_likely' and active and tier = 'plus' limit 1)),
  'P0001',
  'This game needs a partner',
  'a solo user is still refused Who''s More Likely To'
);

select throws_ok(
  format($$select public.start_deck_session(%L)$$,
    (select id from public.game_decks where tier = 'premium' and active limit 1)),
  'P0001',
  'This deck requires Premium',
  'a Plus user is still refused a Premium deck'
);

select * from finish();
rollback;
