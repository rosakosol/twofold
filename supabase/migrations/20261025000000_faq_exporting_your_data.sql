-- ---------------------------------------------------------------------------
-- An FAQ entry for exporting your data while you are still together
-- ---------------------------------------------------------------------------
--
-- There are now three ways to take a copy out of Twofold, and the FAQ described one of them —
-- the archive export, mentioned in passing inside the two entries about disconnecting, where
-- someone looking for "can I download my data" would never think to look.
--
-- The one that was missing is the one that answers that question: Settings -> Help -> Export your
-- data, which is ungated, works while the relationship is live, and writes CSV or JSON. It did not
-- exist when the other entries were written.
--
-- Also names what is deliberately *not* in it. The Relationship Record is Premium, and someone
-- reading this entry is exactly the person about to wonder why their export has no readable
-- document in it; better that they read the reason here than conclude the export is broken.
--
-- Idempotent insert, guarded — faq_entries is live-edited through the Studio FAQ tool.

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'Can I download a copy of my data?',
  'Yes, on any plan and at any time. Go to Settings → Help → Export your data. You choose what to include — trips, memories and their photos, flights, games — and whether you want spreadsheets (CSV, which open in Numbers, Excel or Google Sheets) or a data file (JSON, for moving your information somewhere else). Photos come out as ordinary image files. Large exports download the photos as they go, so they are best done on Wi-Fi. If a relationship has ended, the same export is on each archive in Settings → Archived Data, and is worth doing before its 90 days are up. The Relationship Record — your story written out as a PDF or Word document to keep or print — is a separate, Premium feature, and is not part of a data export.',
  109
where not exists (
  select 1 from public.faq_entries
  where question = 'Can I download a copy of my data?'
);

do $$
begin
  if not exists (
    select 1 from public.faq_entries where question = 'Can I download a copy of my data?'
  ) then
    raise exception 'FAQ entry was not created';
  end if;
end;
$$;
