-- A name of the traveller's own for a document that isn't a boarding pass or an itinerary.
--
-- `doc_type` has always had an 'other' bucket, but everything in it rendered as the same generic
-- "Travel documents" — so a visa, travel insurance and a hotel confirmation attached to one flight
-- were three identical-looking rows. This is what the traveller called it.
--
-- Nullable, and only meaningful for doc_type = 'other': the other two types carry their own fixed
-- names ("Boarding pass", "Itinerary"), and letting a custom label override those would let one
-- boarding pass be called something else on a screen where the label is how you tell the rows
-- apart. The check enforces that rather than leaving it to the client.
--
-- Deliberately not reusing `original_filename`, which is the file's real name on the device and is
-- shown alongside this — overloading it would make "IMG_4821.HEIC" and "Visa" the same field.

alter table public.flight_documents
  add column custom_label text,
  add constraint flight_documents_custom_label_only_for_other
    check (custom_label is null or doc_type = 'other');
