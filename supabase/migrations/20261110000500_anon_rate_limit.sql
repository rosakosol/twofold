-- A rate limiter for callers who have no account, because `/api/support` is an open mail relay.
--
-- ---------------------------------------------------------------------------
-- What it is protecting
-- ---------------------------------------------------------------------------
--
-- `site/src/app/api/support/route.ts` sends two emails per POST. The first goes to our own support
-- address, which is the point of the form. The second goes to `input.email` — an address the
-- caller chose — from our own authenticated Zoho mailbox, carrying up to 5000 characters the
-- caller wrote. There is no rate limit, no CAPTCHA and no proof that the sender controls the
-- address; the only bot control is a honeypot field. So it is an unauthenticated way to send
-- attacker-written mail, from twofoldapp.com.au, to anybody — which costs the sending quota that
-- `/api/waitlist` and the iOS help path share, and costs the domain's reputation, which is not
-- recoverable on the same timescale.
--
-- ---------------------------------------------------------------------------
-- Why not `consume_rate_limit`
-- ---------------------------------------------------------------------------
--
-- That one keys on `auth.uid()` and raises without one, and `rate_limit_events.user_id` is a
-- foreign key to `profiles`. Neither can describe a visitor who has no account, which is exactly
-- who this endpoint is for.
--
-- ---------------------------------------------------------------------------
-- No address is stored
-- ---------------------------------------------------------------------------
--
-- The subject — an IP or an email — is hashed here with a per-project salt that lives in `private`
-- and is generated once, so the table holds an opaque string and never an identifier. Salted
-- rather than a bare digest because the IPv4 space is small enough to enumerate: an unsalted
-- sha256 of an address is reversible in minutes, which would make this table a log of who
-- contacted support.
--
-- The hash is computed here rather than in the route so the salt never leaves the database, and
-- so a second caller of this function cannot get the hashing wrong.
--
-- Honest about the residual: the route passes the caller's IP, and anyone calling this RPC
-- directly may pass somebody else's. The worst that buys is stopping a person they already know
-- the IP of from using the support form for an hour, which is a smaller harm than the relay and
-- needs information they had to have already.

create table if not exists private.anon_rate_limit_salt (
  salt text primary key
);

-- Two uuids rather than pgcrypto's gen_random_bytes, which needs an extension this schema does
-- not otherwise require. ~244 bits, generated once and never rotated — rotating it would reset
-- every live window, which is the one thing a rate limiter must not do on deploy.
insert into private.anon_rate_limit_salt (salt)
select gen_random_uuid()::text || gen_random_uuid()::text
where not exists (select 1 from private.anon_rate_limit_salt);

create table if not exists public.anon_rate_limit_events (
  id bigint generated always as identity primary key,
  bucket text not null,
  subject_hash text not null,
  occurred_at timestamptz not null default now()
);

comment on table public.anon_rate_limit_events is
  'Rate-limit ledger for callers with no account. `subject_hash` is a salted digest of an IP or '
  'an email — never the value itself. Deny-all to clients; written only by consume_anon_rate_limit.';

create index if not exists anon_rate_limit_events_lookup
  on public.anon_rate_limit_events (bucket, subject_hash, occurred_at desc);
-- For the retention sweep, which is the one query that does not know a bucket.
create index if not exists anon_rate_limit_events_retention
  on public.anon_rate_limit_events (occurred_at);

alter table public.anon_rate_limit_events enable row level security;

create or replace function public.consume_anon_rate_limit(
  p_bucket text,
  p_subject text,
  p_limit integer,
  p_window interval
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  c_max_window constant interval := interval '1 day';
  v_salt text;
  v_hash text;
  v_used integer;
begin
  if p_bucket is null or length(p_bucket) not between 1 and 64 then
    raise exception 'p_bucket must be 1-64 characters';
  end if;
  if p_subject is null or length(p_subject) not between 1 and 320 then
    raise exception 'p_subject must be 1-320 characters';
  end if;
  if p_limit is null or p_limit < 1 then
    raise exception 'p_limit must be at least 1';
  end if;
  if p_window is null or p_window <= interval '0' or p_window > c_max_window then
    raise exception 'p_window must be positive and at most %', c_max_window;
  end if;

  select salt into v_salt from private.anon_rate_limit_salt limit 1;
  -- The bucket is inside the digest, so the same address in two buckets does not collide and one
  -- endpoint's ledger cannot be read across to another.
  v_hash := encode(sha256((v_salt || ':' || p_bucket || ':' || lower(p_subject))::bytea), 'hex');

  -- Retention only, and on the constant — never on `p_window`. 20261110000200 is the migration
  -- that had to unpick exactly this: a purge cutoff built from a caller's argument is a caller who
  -- can empty their own ledger by asking for a one-microsecond window.
  delete from public.anon_rate_limit_events
  where occurred_at <= now() - c_max_window;

  select count(*) into v_used
  from public.anon_rate_limit_events
  where bucket = p_bucket and subject_hash = v_hash and occurred_at > now() - p_window;

  -- Returns before recording, like `consume_rate_limit`: a refused attempt is not written, so a
  -- caller cannot extend their own lockout by retrying and the window always drains on schedule.
  if v_used >= p_limit then
    return false;
  end if;

  insert into public.anon_rate_limit_events (bucket, subject_hash) values (p_bucket, v_hash);
  return true;
end;
$$;

-- anon deliberately, unlike every other function closed this week: the caller is a visitor with no
-- session, and the website's server components hold nothing stronger than the publishable key.
-- What that grant exposes is the ability to consume your own quota, which is what an attacker
-- would be trying to avoid.
revoke all on function public.consume_anon_rate_limit(text, text, integer, interval) from public;
grant execute on function public.consume_anon_rate_limit(text, text, integer, interval)
  to anon, authenticated, service_role;
