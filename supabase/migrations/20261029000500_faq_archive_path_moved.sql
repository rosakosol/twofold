-- ---------------------------------------------------------------------------
-- The archive lives under Help now, and two FAQ answers say otherwise
-- ---------------------------------------------------------------------------
--
-- "Archived Data" used to sit inside Settings → Help → Disconnect my partner, and that row is
-- gated on having a partner — so the screen was unreachable for exactly the people whose archive
-- had just started its 90-day countdown, and who several places in the app tell to go and export
-- it. It is now its own row in Settings → Help, ungated.
--
-- These two answers name the old path. Targeted `replace` rather than rewriting the answers
-- wholesale, because `faq_entries` is live-edited through the Studio FAQ tool: anything else in
-- them may have been reworded since it was seeded, and replacing the whole row would silently
-- discard that.
--
-- Both spellings are handled — one answer uses an arrow, the other an ASCII "->".

update public.faq_entries
set answer = replace(answer, 'Settings → Archived Data', 'Settings → Help → Archived Data')
where answer like '%Settings → Archived Data%';

update public.faq_entries
set answer = replace(answer, 'Settings -> Archived Data', 'Settings -> Help -> Archived Data')
where answer like '%Settings -> Archived Data%';

do $$
begin
  if exists (
    select 1 from public.faq_entries
    where answer like '%Settings → Archived Data%'
       or answer like '%Settings -> Archived Data%'
  ) then
    raise exception 'An FAQ answer still names the old archive path';
  end if;
end;
$$;
