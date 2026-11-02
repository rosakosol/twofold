-- Drops the feedback board's notification outbox and the two triggers that filled it.
--
-- trg_developer_updates_notify and trg_feature_requests_status_change_notify wrote one row per voter
-- or subscriber into feature_notification_outbox, and nothing ever read it: no edge function, cron
-- job, site page or app screen sends those notifications. It only piled up copies of update bodies
-- and feature titles. 20261120000000 kept it for the owner to decide on; they decided to drop it.
--
-- The table's rows go with it. Nothing else references the table, so no cascade is needed, and
-- the drop fails loudly if that has changed.

drop trigger if exists trg_developer_updates_notify on public.developer_updates;
drop trigger if exists trg_feature_requests_status_change_notify on public.feature_requests;

drop function if exists public.enqueue_developer_update_notifications();
drop function if exists public.enqueue_feature_status_change_notifications();

drop table if exists public.feature_notification_outbox;
