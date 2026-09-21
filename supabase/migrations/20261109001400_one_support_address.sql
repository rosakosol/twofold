-- ---------------------------------------------------------------------------
-- One address, and it is the one the forms already use
-- ---------------------------------------------------------------------------
--
-- Two addresses were in circulation. `support@twofoldapp.com.au` is where
-- `submit-help-message` and the website's contact form deliver, and it is the only one anything
-- automated reads. `hello@twofoldapp.com.au` is the one users were actually told to write to
-- almost everywhere else — the FAQ, the privacy policy, the terms, and several in-app error
-- messages.
--
-- That split mattered more once support submissions became rows. Anything sent to hello@ produced
-- no ticket and no trace, and the abuse-reporting entry below is the sharpest case: it directs
-- people to hello@ and promises a response within 48 hours, so the promise rested on somebody
-- watching the address the system knew nothing about.
--
-- Everything now points at support@. The code and seed scripts are changed in place; these rows
-- are already in production, so they are rewritten here.
--
-- ---------------------------------------------------------------------------
-- A replace, not a rewrite
-- ---------------------------------------------------------------------------
--
-- The answers are long and carefully worded, and retyping them to change an address is how a
-- sentence quietly loses a clause. `replace()` touches the address and nothing else, and re-running
-- it finds nothing left to change rather than erroring — so this is safe to apply to an
-- environment that has already had it, and to one seeded fresh from the migrations above, where
-- the old address never existed.

update public.faq_entries
set answer = replace(answer, 'hello@twofoldapp.com.au', 'support@twofoldapp.com.au')
where answer like '%hello@twofoldapp.com.au%';

update public.faq_entries
set question = replace(question, 'hello@twofoldapp.com.au', 'support@twofoldapp.com.au')
where question like '%hello@twofoldapp.com.au%';

-- Nothing should be left. A row that still carries the old address after this is a row added
-- between writing and applying it, which is worth failing loudly for rather than shipping past.
do $$
declare
  v_left integer;
begin
  select count(*) into v_left from public.faq_entries
  where answer like '%hello@twofoldapp.com.au%' or question like '%hello@twofoldapp.com.au%';
  if v_left > 0 then
    raise exception '% FAQ entries still reference hello@twofoldapp.com.au', v_left;
  end if;
end
$$;
