-- ---------------------------------------------------------------------------
-- "It's your turn" for Chess and Connect 4
-- ---------------------------------------------------------------------------
--
-- Chess and Connect 4 are the only turn-based games in the app, and until now a move sent the
-- opponent nothing. Both stores notify on `game_results_ready` when a game *ends*, and both offer
-- a manual "Send Reminder" — so between those two moments a game simply stalled until the other
-- person happened to open the app. Realtime delivers moves instantly, but only to a foreground
-- app, which is precisely the case this is about.
--
-- It also fed a second problem: `archive-stale-games` expires these after inactivity, so a game
-- could quietly die because neither player knew it was their move.
--
-- ---------------------------------------------------------------------------
-- Why a trigger on `game_moves`
-- ---------------------------------------------------------------------------
--
-- The two games do not share a write path — Connect 4 is the `play_connect_four_move` RPC, chess
-- is the `play-chess-move` Edge Function, because chess legality is `chess.js`'s job and not
-- Postgres's. What they *do* share is the table: both insert the move into `game_moves`, and
-- neither game's board exists anywhere else.
--
-- So the notification hangs off the insert rather than off either caller. One implementation, one
-- cooldown, and no way for a future third turn-based game to forget to send it. It also means
-- neither the RPC nor the Edge Function had to be reopened to add this.
--
-- `after insert ... for each row`, so it sees the move as stored. `net.http_post` queues the
-- request in pg_net's own table rather than sending inline, so it does not hold the move's
-- transaction open on a network call — and a transaction that rolls back takes the queued request
-- with it, which is what keeps a notification from going out for a move that never happened.

-- ---------------------------------------------------------------------------
-- The preference
-- ---------------------------------------------------------------------------
--
-- Its own column rather than riding on `partner_game_started`. A turn notification arrives
-- repeatedly through a single game, where the others fire once per event — someone who wants to
-- know their partner started a game does not necessarily want a buzz every move, and the reverse
-- is just as reasonable. A shared toggle would force one choice on both.
--
-- Defaults true, like every other column here: a missing row means "everything on", which is what
-- `notify-couple-event` assumes when it finds no preferences row at all.
alter table public.notification_preferences
  add column if not exists partner_game_turn boolean not null default true;

comment on column public.notification_preferences.partner_game_turn is
  'Push when the partner makes a move in a turn-based game (Chess, Connect 4) and it becomes '
  'this profile''s turn. Separate from partner_game_started because it fires repeatedly within '
  'one game rather than once.';

-- ---------------------------------------------------------------------------
-- The cooldown
-- ---------------------------------------------------------------------------
--
-- Not `consume_rate_limit`: that keys on `auth.uid()` and raises when it is null, which is exactly
-- the case here — the chess path reaches this trigger through an Edge Function running as the
-- service role, with no end-user JWT on the connection.
--
-- It is also a different shape of limit. A counter answers "how many in a window"; what this wants
-- is "not again for a while", per conversation, per recipient. A fast back-and-forth between two
-- people who are both clearly present should produce one notification, not one per move.
create table if not exists private.game_turn_notices (
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  last_sent_at timestamptz not null default now(),
  primary key (session_id, recipient_id)
);

comment on table private.game_turn_notices is
  'When each player was last told it is their turn, per session. In `private` because it is '
  'bookkeeping no client needs to read, and because nothing good comes of a client being able to '
  'clear its partner''s cooldown.';

create or replace function private.notify_game_turn()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Long enough that a rally between two present players produces one push rather than a dozen;
  -- short enough that somebody who put their phone down hears within a few minutes. The first
  -- move after a quiet spell always sends — this delays repeats, never the one that matters.
  c_cooldown constant interval := interval '5 minutes';
  v_couple_id uuid;
  v_game_type text;
  v_status text;
  v_recipient uuid;
  v_mover_name text;
  v_sent boolean;
  project_url text;
  service_key text;
begin
  select gs.couple_id, gs.game_type, gs.status
    into v_couple_id, v_game_type, v_status
  from public.game_sessions gs
  where gs.id = new.session_id;

  -- Solo sessions have nobody to tell. A finished game is the `game_results_ready` push's
  -- business, and saying "your turn" about a game that just ended would be wrong twice over.
  if v_couple_id is null or v_game_type not in ('chess', 'connect_four') or v_status <> 'active' then
    return null;
  end if;

  select case when c.partner_a_id = new.player_id then c.partner_b_id else c.partner_a_id end
    into v_recipient
  from public.couples c
  where c.id = v_couple_id;

  if v_recipient is null or v_recipient = new.player_id then
    return null;
  end if;

  -- Before the claim, not after. Claiming first would start a five-minute cooldown for a
  -- notification that was never sent, so a misconfigured Vault would cost the *next* move its
  -- push too — turning a silent outage into a longer silent outage.
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into service_key from vault.decrypted_secrets where name = 'service_role_key';

  if project_url is null or service_key is null then
    raise notice 'notify_game_turn: project_url/service_role_key not set in Vault, skipping';
    return null;
  end if;

  -- Claim the right to send, atomically. The `where` on the conflict path is what makes this a
  -- cooldown rather than a check-then-write race: two moves landing together leave exactly one
  -- with a row returned, because the second finds `last_sent_at` already moved.
  insert into private.game_turn_notices (session_id, recipient_id, last_sent_at)
  values (new.session_id, v_recipient, now())
  on conflict (session_id, recipient_id) do update
    set last_sent_at = now()
    where private.game_turn_notices.last_sent_at <= now() - c_cooldown
  returning true into v_sent;

  if v_sent is not true then
    return null;
  end if;

  select p.first_name into v_mover_name from public.profiles p where p.id = new.player_id;

  -- Through an Edge Function rather than straight to APNs, because signing an APNs JWT is not
  -- something SQL can do. `notify-game-turn` rather than `notify-couple-event`: that one derives
  -- the actor from the caller's JWT and 401s without one, and there is no end user on this
  -- connection at all. It reuses the same copy, preference row and token fan-out.
  perform net.http_post(
    url := project_url || '/functions/v1/notify-game-turn',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := jsonb_build_object(
      'eventType', 'game_turn',
      'actorId', new.player_id,
      'actorName', coalesce(nullif(v_mover_name, ''), 'Your partner'),
      'recipientId', v_recipient,
      'sessionId', new.session_id,
      'gameType', v_game_type
    )
  );

  return null;
end;
$$;

comment on function private.notify_game_turn() is
  'Tells the opponent it is their move, at most once every five minutes per session. Hangs off '
  'game_moves because Chess and Connect 4 share that table and nothing else in their write paths.';

drop trigger if exists trg_game_moves_notify_turn on public.game_moves;

create trigger trg_game_moves_notify_turn
  after insert on public.game_moves
  for each row execute function private.notify_game_turn();
