-- Future-proofing hook for email/push notifications on status changes and developer
-- updates — this migration only builds the fan-out queue itself, not a sender. A
-- future worker (Vercel cron, or a Supabase Edge Function on the same pg_cron pattern
-- this project already uses for refresh-due-flights) would drain it with the
-- service-role key: `select * from feature_notification_outbox where processed_at is
-- null order by created_at limit 100`, send, then set processed_at.
--
-- RLS enabled with ZERO policies — this table is invisible to anon/authenticated by
-- design (default-deny). Only the security-definer trigger functions below ever write
-- to it, and only a future service-role worker would ever read it. That's the correct
-- posture for an internal queue, not an oversight.
create table public.feature_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_requests (id) on delete cascade,
  event_type text not null check (event_type in ('status_changed', 'developer_update_posted')),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index feature_notification_outbox_recipient_idx on public.feature_notification_outbox (recipient_id);
create index feature_notification_outbox_unprocessed_idx
  on public.feature_notification_outbox (created_at) where processed_at is null;

alter table public.feature_notification_outbox enable row level security;

create or replace function public.enqueue_feature_status_change_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.feature_notification_outbox (feature_id, event_type, recipient_id, payload)
  select
    new.id,
    'status_changed',
    recipient_id,
    jsonb_build_object(
      'feature_title', new.title,
      'feature_slug', new.slug,
      'old_status', old.status,
      'new_status', new.status
    )
  from (
    select user_id as recipient_id from public.feature_votes where feature_id = new.id
    union
    select user_id as recipient_id from public.feature_subscribers where feature_id = new.id
  ) recipients;

  return new;
end;
$$;

create trigger trg_feature_requests_status_change_notify
  after update of status on public.feature_requests
  for each row
  when (old.status is distinct from new.status)
  execute function public.enqueue_feature_status_change_notifications();

create or replace function public.enqueue_developer_update_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.feature_notification_outbox (feature_id, event_type, recipient_id, payload)
  select
    new.feature_id,
    'developer_update_posted',
    recipient_id,
    jsonb_build_object('update_body', new.body)
  from (
    select user_id as recipient_id from public.feature_votes where feature_id = new.feature_id
    union
    select user_id as recipient_id from public.feature_subscribers where feature_id = new.feature_id
  ) recipients;

  return new;
end;
$$;

create trigger trg_developer_updates_notify
  after insert on public.developer_updates
  for each row execute function public.enqueue_developer_update_notifications();
