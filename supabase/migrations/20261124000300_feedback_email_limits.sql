-- Limits on the "your idea is on the board" email and on the posts that trigger it (security review, F3).
--
-- Sign-up does not prove an address, so an account can belong to an address its holder does not own.
-- Each post then earned one email to that address, carrying text the poster wrote, from our domain,
-- with no limit on either. That is unwanted mail to somebody else and a risk to the reputation of the
-- mailbox support replies come from.
--
-- Three limits, all in the database so that neither the site's route nor a direct call can skip them:
--
--   * 3 confirmation emails a day per account. One address is one account, so this is also the most
--     any one address can receive.
--   * 100 confirmation emails a day in total, for many accounts acting together. Reaching it costs real
--     people a courtesy email and nothing else, because their post still goes up.
--   * 10 posts a day per account, because the board is public and the posts are the attacker's text
--     too. An admin is exempt, and so is anything with no signed-in user behind it.
--
-- A refused email is quiet, as the other refusals here are. A refused post raises, so the form can say
-- why. The numbers are well above what the board has ever needed from one person.

create or replace function public.claim_feedback_confirmation(p_feature_id uuid)
returns table (
  email text,
  display_name text,
  title text,
  description text,
  category text,
  slug text,
  token uuid
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_request public.feature_requests%rowtype;
  v_allowed boolean;
begin
  select * into v_request from public.feature_requests r where r.id = p_feature_id;
  if v_request.id is null or v_request.author_id is distinct from auth.uid()
     or v_request.created_at < now() - interval '1 hour' then
    return;
  end if;

  select lower(u.email) into v_email from auth.users u where u.id = auth.uid();
  if v_email is null then
    return;
  end if;
  perform public.email_preferences_token_for(v_email);
  if not (select p.feedback_updates from public.email_preferences p where p.email = v_email) then
    return;
  end if;

  insert into public.feedback_confirmations (feature_id) values (p_feature_id)
  on conflict (feature_id) do nothing;
  if not found then
    return;
  end if;

  -- After the claim, so asking twice about one post does not spend the allowance twice. A post that
  -- is refused here stays claimed and gets no email later, which is the right outcome for a courtesy.
  select r.allowed into v_allowed
  from public.consume_rate_limit('feedback_confirmation', 3, interval '1 day') r;
  if not v_allowed then
    return;
  end if;

  if not public.consume_anon_rate_limit('feedback_confirmation_all', 'all', 100, interval '1 day') then
    return;
  end if;

  return query
    select v_email,
      coalesce(nullif(pr.first_name, ''), 'there'),
      v_request.title,
      v_request.description,
      v_request.category::text,
      v_request.slug,
      p.token
    from public.email_preferences p
    left join public.profiles pr on pr.id = auth.uid()
    where p.email = v_email;
end;
$$;

revoke execute on function public.claim_feedback_confirmation(uuid) from public, anon;
grant execute on function public.claim_feedback_confirmation(uuid) to authenticated;

create or replace function public.enforce_feature_request_insert_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean;
begin
  if public.is_feedback_admin() then
    return new;
  end if;

  -- A failed insert rolls this back with it, so retrying after a slug collision costs nothing.
  if auth.uid() is not null then
    select r.allowed into v_allowed
    from public.consume_rate_limit('feature_request_insert', 10, interval '1 day') r;
    if not v_allowed then
      raise exception 'feature_request_limit' using
        errcode = 'P0001',
        hint = 'This account has posted as many feature requests as it can today.';
    end if;
  end if;

  new.status := 'requested';
  new.is_pinned := false;
  new.upvote_count := 0;
  new.comment_count := 0;
  new.merged_into := null;
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.enforce_feature_request_insert_scope() from public, anon, authenticated;
