-- ---------------------------------------------------------------------------
-- Two FAQ entries: how to report someone, and what happens to a shared flight email
-- ---------------------------------------------------------------------------
--
-- `faq_entries` is the single source for both the marketing site's /faq page and the app's
-- Settings -> Support screen, so it is the most-read of the three places this is documented.
--
-- Reporting: there was nothing to read, because until now there was nothing to do. Apple's
-- Guideline 1.2 asks for a reporting mechanism *and* timely responses, and a response window
-- nobody can find is not one anyone can rely on.
--
-- The flight email is the older gap and the more surprising one. Sharing a booking confirmation
-- into Twofold sends its subject, body, and sometimes text from an attached PDF to OpenAI. The
-- privacy policy has a whole section on it; the FAQ did not mention the feature at all, let alone
-- that a third party reads the email. Of everything Twofold does with data, this is the one most
-- likely to make someone stop and think, and it was missing from the surface people actually read.
--
-- OpenAI is named here, as it is in the policy and unlike every other provider, for the same
-- reason: the sentence makes a specific promise about training, and a promise about a named
-- company is worth something that a promise about "an AI provider" is not.
--
-- Idempotent inserts. faq_entries is live-edited through the Studio FAQ tool, so these must not
-- duplicate an entry someone has already written.

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'What happens to a flight email I share with Twofold?',
  'You can share a booking confirmation or boarding pass into Twofold instead of typing a flight in by hand. The app holds it on your device until you open it and ask for it to be read. If you go ahead, the email''s subject and text - and, when those are not enough, text pulled from an attached PDF - are sent to OpenAI, which picks out the flight number, airports and times and sends them back. Only what you shared is sent, only at the moment you ask, and OpenAI does not use it to train its models. Close the screen without confirming and nothing leaves your phone. You can always add a flight by hand instead.',
  107
where not exists (
  select 1 from public.faq_entries
  where question = 'What happens to a flight email I share with Twofold?'
);

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'How do I report or block someone?',
  'If someone sends you something abusive, or is using Twofold to harm or monitor you, tell us. "Report Abuse" is on a connection request before you accept it, and on your partner in Settings → Disconnect Partner; you can also email hello@twofoldapp.com.au. We aim to respond within 48 hours, and we never tell the person that you reported them. You can block someone whether or not you report them: blocking a request stops them sending another, and blocking a partner disconnects you first. Either way they are not told and cannot reach you again. What the two of you shared is archived as normal and deleted on the usual 90-day timer - blocking does not delete it sooner or keep it longer.',
  108
where not exists (
  select 1 from public.faq_entries
  where question = 'How do I report or block someone?'
);

do $$
declare
  v_missing text[];
begin
  select array_agg(q) into v_missing
  from unnest(array[
    'What happens to a flight email I share with Twofold?',
    'How do I report or block someone?'
  ]) as q
  where not exists (select 1 from public.faq_entries f where f.question = q);

  if v_missing is not null then
    raise exception 'FAQ entries were not created: %', v_missing;
  end if;
end;
$$;
