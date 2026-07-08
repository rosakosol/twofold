-- Adds an IANA timezone identifier to places, powering the "It's 3am for
-- Rosa right now" timezone cards. Nullable: cities added later via live city
-- search may not have one resolved yet.

alter table public.places add column timezone text;

update public.places set timezone = 'Australia/Melbourne' where city = 'Melbourne' and country = 'Australia';
update public.places set timezone = 'Asia/Singapore' where city = 'Singapore' and country = 'Singapore';
update public.places set timezone = 'Asia/Bangkok' where city = 'Bangkok' and country = 'Thailand';
update public.places set timezone = 'Asia/Tokyo' where city = 'Tokyo' and country = 'Japan';
update public.places set timezone = 'Europe/London' where city = 'London' and country = 'United Kingdom';
update public.places set timezone = 'America/New_York' where city = 'New York' and country = 'United States';
update public.places set timezone = 'Australia/Sydney' where city = 'Sydney' and country = 'Australia';
