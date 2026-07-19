-- Invite codes expired after 14 days — a long window given they're also now rate-limited but
-- still guessable in principle. Shortens new codes to 3 days; doesn't touch already-outstanding
-- pending codes, so an invite someone's mid-way through sharing/redeeming right now doesn't
-- suddenly become invalid underneath them.

alter table public.invite_codes
  alter column expires_at set default (now() + interval '3 days');
