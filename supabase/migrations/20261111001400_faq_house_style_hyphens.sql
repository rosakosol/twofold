-- Nineteen of twenty-three FAQ rows use an em dash, against the house style.
--
-- The rule is a plain hyphen, never an em or en dash — it is stated in
-- `site/src/lib/marketing/faqFallback.ts`, whose own comment claims "the live rows and these
-- mirrored strings both follow it". The mirrored strings do. The rows stopped, one migration at a
-- time, and nothing was checking.
--
-- It matters because these rows are not only web copy. The iOS app renders the same text in
-- Settings -> Help, where it sits beside app copy that uses hyphens, and `faqFallback.ts` is a
-- character-for-character mirror of the rows for the cold-start path — so a row with an em dash and
-- a fallback with a hyphen are the same answer punctuated two ways, on the same page, depending on
-- whether Supabase answered.
--
-- ---------------------------------------------------------------------------
-- Why replace() and not a rewrite
-- ---------------------------------------------------------------------------
--
-- Every other migration that has touched this table restates the whole answer. This one must not:
-- the Studio FAQ tool (`site/src/sanity/tools/FaqTool.tsx`) writes `faq_entries` directly as the
-- signed-in admin, so a row in production may have been edited since the migration that last set
-- it. Restating the text would silently revert those edits, and nothing about a punctuation pass
-- justifies overwriting content.
--
-- `replace()` changes the character and nothing else, whatever the row currently says, and is
-- idempotent — a second run finds no em dashes and updates nothing.
--
-- ---------------------------------------------------------------------------
-- Safe to do blindly, because the spacing was checked first
-- ---------------------------------------------------------------------------
--
-- All 31 occurrences are ' — ', space on both sides, so ' - ' is what comes out and the result is
-- the house style exactly. An unspaced em dash would have needed care — 'word—word' becoming
-- 'word-word' invents a compound — and there are none. There are also no en dashes, non-breaking
-- hyphens or minus signs, so this is the only character to fix.

update public.faq_entries
set question = replace(question, '—', '-'),
    answer = replace(answer, '—', '-')
where question like '%—%' or answer like '%—%';

do $$
declare
  v_remaining int;
begin
  select count(*) into v_remaining
  from public.faq_entries
  where question like '%—%' or answer like '%—%';

  if v_remaining > 0 then
    raise exception 'em dashes still present in % FAQ rows', v_remaining;
  end if;
end;
$$;
