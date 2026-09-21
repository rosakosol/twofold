-- ---------------------------------------------------------------------------
-- The feedback board, in source control at last
-- ---------------------------------------------------------------------------
--
-- Seven tables, two enums, nine functions, seven triggers and twenty-two policies that have never
-- had a migration. They were created by hand in the dashboard and have existed only in the linked
-- project ever since, which means:
--
--   * A fresh database does not have them. `supabase db reset`, a CI run and a staging project all
--     produce a schema the website cannot run against, and every query in `site/src/lib/queries`
--     fails there.
--   * `supabase gen types typescript --local` DELETES them from `site/src/lib/db/types.ts`, because
--     they are genuinely absent locally. That is not hypothetical — it happened while writing the
--     account portal, and the build broke in nine files at once.
--   * Nothing reviews changes to them. A policy edited in the dashboard leaves no diff, no history
--     and nothing to notice.
--
-- This is the same hole 20260830000850 was written to close for `feedback_admins` and
-- `is_feedback_admin()` — its own header describes a fresh database dying with "function
-- public.is_feedback_admin() does not exist". That migration captured the two objects that had
-- already caused an outage. These are the rest of them.
--
-- ---------------------------------------------------------------------------
-- Read back from production, and kept in its words rather than ours
-- ---------------------------------------------------------------------------
--
-- Every statement below is `pg_dump` output from the linked project, not a reconstruction. The
-- quoted, upper-case style is pg_dump's and is deliberately left alone: the point of this file is
-- to reproduce production exactly, and restyling six hundred lines of DDL by hand — twenty-two
-- policy predicates, nine function bodies — is an invitation to a transcription error that would
-- be invisible until a policy behaved differently here than there. Correctness over house style,
-- and the house style is not worth a subtly wrong security policy.
--
-- What was dropped: the `OWNER TO "postgres"` statements, since migrations already run as postgres.
--
-- What was added: idempotency. `create type`, `add constraint` and `create policy` have no
-- `if not exists`, so each is guarded — on `pg_type`, on `pg_constraint`, and by a preceding
-- `drop policy if exists` respectively.
--
-- ---------------------------------------------------------------------------
-- This must NOT re-run on production
-- ---------------------------------------------------------------------------
--
-- Production already has every object here. Mark it applied out of band, exactly as 20260830000850
-- says it did:
--
--     supabase migration repair --status applied 20261109000600
--
-- Every statement is idempotent anyway, so applying it to an environment that already has these
-- objects is a no-op rather than an error. The repair is belt and braces, and it also stops the
-- `drop policy if exists` pairs below from briefly dropping a live policy on a running database.
--
-- Depends on `pg_trgm` (feature_requests_title_trgm_idx uses gin_trgm_ops), created by
-- 20260708102734, and on `touch_updated_at`, created by the same.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
--
-- `create type` has no `if not exists`, so each is guarded on pg_type.

do $cap$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'feedback_request_category') then
    CREATE TYPE "public"."feedback_request_category" AS ENUM (
        'flights',
        'memories',
        'games',
        'widgets',
        'notifications',
        'relationship',
        'general'
    );
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'feedback_request_status') then
    CREATE TYPE "public"."feedback_request_status" AS ENUM (
        'requested',
        'considering',
        'planned',
        'in_progress',
        'released',
        'closed'
    );
  end if;
end $cap$;


-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
--
-- pg_dump already emits `if not exists` for these.

CREATE TABLE IF NOT EXISTS "public"."developer_updates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "feature_id" "uuid" NOT NULL,
    "author_id" "uuid",
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "developer_updates_body_check" CHECK ((("char_length"("body") >= 1) AND ("char_length"("body") <= 4000)))
);

CREATE TABLE IF NOT EXISTS "public"."feature_bookmarks" (
    "feature_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."feature_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "feature_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feature_comments_body_check" CHECK ((("char_length"("body") >= 1) AND ("char_length"("body") <= 4000)))
);

CREATE TABLE IF NOT EXISTS "public"."feature_notification_outbox" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "feature_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    CONSTRAINT "feature_notification_outbox_event_type_check" CHECK (("event_type" = ANY (ARRAY['status_changed'::"text", 'developer_update_posted'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."feature_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "category" "public"."feedback_request_category" NOT NULL,
    "status" "public"."feedback_request_status" DEFAULT 'requested'::"public"."feedback_request_status" NOT NULL,
    "author_id" "uuid",
    "upvote_count" integer DEFAULT 0 NOT NULL,
    "comment_count" integer DEFAULT 0 NOT NULL,
    "is_pinned" boolean DEFAULT false NOT NULL,
    "merged_into" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feature_requests_title_check" CHECK ((("char_length"("title") >= 3) AND ("char_length"("title") <= 140)))
);

CREATE TABLE IF NOT EXISTS "public"."feature_subscribers" (
    "feature_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."feature_votes" (
    "feature_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


-- ---------------------------------------------------------------------------
-- Primary keys, uniques and foreign keys
-- ---------------------------------------------------------------------------
--
-- `add constraint` has no `if not exists` either, so each is guarded on pg_constraint.

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'developer_updates_pkey' and conrelid = 'public.developer_updates'::regclass) then
    ALTER TABLE ONLY "public"."developer_updates"
        ADD CONSTRAINT "developer_updates_pkey" PRIMARY KEY ("id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_bookmarks_pkey' and conrelid = 'public.feature_bookmarks'::regclass) then
    ALTER TABLE ONLY "public"."feature_bookmarks"
        ADD CONSTRAINT "feature_bookmarks_pkey" PRIMARY KEY ("feature_id", "user_id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_comments_pkey' and conrelid = 'public.feature_comments'::regclass) then
    ALTER TABLE ONLY "public"."feature_comments"
        ADD CONSTRAINT "feature_comments_pkey" PRIMARY KEY ("id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_notification_outbox_pkey' and conrelid = 'public.feature_notification_outbox'::regclass) then
    ALTER TABLE ONLY "public"."feature_notification_outbox"
        ADD CONSTRAINT "feature_notification_outbox_pkey" PRIMARY KEY ("id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_requests_pkey' and conrelid = 'public.feature_requests'::regclass) then
    ALTER TABLE ONLY "public"."feature_requests"
        ADD CONSTRAINT "feature_requests_pkey" PRIMARY KEY ("id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_requests_slug_key' and conrelid = 'public.feature_requests'::regclass) then
    ALTER TABLE ONLY "public"."feature_requests"
        ADD CONSTRAINT "feature_requests_slug_key" UNIQUE ("slug");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_subscribers_pkey' and conrelid = 'public.feature_subscribers'::regclass) then
    ALTER TABLE ONLY "public"."feature_subscribers"
        ADD CONSTRAINT "feature_subscribers_pkey" PRIMARY KEY ("feature_id", "user_id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_votes_pkey' and conrelid = 'public.feature_votes'::regclass) then
    ALTER TABLE ONLY "public"."feature_votes"
        ADD CONSTRAINT "feature_votes_pkey" PRIMARY KEY ("feature_id", "user_id");
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'developer_updates_author_id_fkey' and conrelid = 'public.developer_updates'::regclass) then
    ALTER TABLE ONLY "public"."developer_updates"
        ADD CONSTRAINT "developer_updates_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'developer_updates_feature_id_fkey' and conrelid = 'public.developer_updates'::regclass) then
    ALTER TABLE ONLY "public"."developer_updates"
        ADD CONSTRAINT "developer_updates_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."feature_requests"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_bookmarks_feature_id_fkey' and conrelid = 'public.feature_bookmarks'::regclass) then
    ALTER TABLE ONLY "public"."feature_bookmarks"
        ADD CONSTRAINT "feature_bookmarks_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."feature_requests"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_bookmarks_user_id_fkey' and conrelid = 'public.feature_bookmarks'::regclass) then
    ALTER TABLE ONLY "public"."feature_bookmarks"
        ADD CONSTRAINT "feature_bookmarks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_comments_feature_id_fkey' and conrelid = 'public.feature_comments'::regclass) then
    ALTER TABLE ONLY "public"."feature_comments"
        ADD CONSTRAINT "feature_comments_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."feature_requests"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_comments_user_id_fkey' and conrelid = 'public.feature_comments'::regclass) then
    ALTER TABLE ONLY "public"."feature_comments"
        ADD CONSTRAINT "feature_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_notification_outbox_feature_id_fkey' and conrelid = 'public.feature_notification_outbox'::regclass) then
    ALTER TABLE ONLY "public"."feature_notification_outbox"
        ADD CONSTRAINT "feature_notification_outbox_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."feature_requests"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_notification_outbox_recipient_id_fkey' and conrelid = 'public.feature_notification_outbox'::regclass) then
    ALTER TABLE ONLY "public"."feature_notification_outbox"
        ADD CONSTRAINT "feature_notification_outbox_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_requests_author_id_fkey' and conrelid = 'public.feature_requests'::regclass) then
    ALTER TABLE ONLY "public"."feature_requests"
        ADD CONSTRAINT "feature_requests_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_requests_merged_into_fkey' and conrelid = 'public.feature_requests'::regclass) then
    ALTER TABLE ONLY "public"."feature_requests"
        ADD CONSTRAINT "feature_requests_merged_into_fkey" FOREIGN KEY ("merged_into") REFERENCES "public"."feature_requests"("id") ON DELETE SET NULL;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_subscribers_feature_id_fkey' and conrelid = 'public.feature_subscribers'::regclass) then
    ALTER TABLE ONLY "public"."feature_subscribers"
        ADD CONSTRAINT "feature_subscribers_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."feature_requests"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_subscribers_user_id_fkey' and conrelid = 'public.feature_subscribers'::regclass) then
    ALTER TABLE ONLY "public"."feature_subscribers"
        ADD CONSTRAINT "feature_subscribers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_votes_feature_id_fkey' and conrelid = 'public.feature_votes'::regclass) then
    ALTER TABLE ONLY "public"."feature_votes"
        ADD CONSTRAINT "feature_votes_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."feature_requests"("id") ON DELETE CASCADE;
  end if;
end $cap$;

do $cap$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'feature_votes_user_id_fkey' and conrelid = 'public.feature_votes'::regclass) then
    ALTER TABLE ONLY "public"."feature_votes"
        ADD CONSTRAINT "feature_votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
  end if;
end $cap$;


-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
--
-- `if not exists` added to each; otherwise verbatim.

CREATE INDEX IF NOT EXISTS "developer_updates_feature_id_idx" ON "public"."developer_updates" USING "btree" ("feature_id");

CREATE INDEX IF NOT EXISTS "feature_bookmarks_user_id_idx" ON "public"."feature_bookmarks" USING "btree" ("user_id", "created_at" DESC);

CREATE INDEX IF NOT EXISTS "feature_comments_feature_id_idx" ON "public"."feature_comments" USING "btree" ("feature_id");

CREATE INDEX IF NOT EXISTS "feature_notification_outbox_recipient_idx" ON "public"."feature_notification_outbox" USING "btree" ("recipient_id");

CREATE INDEX IF NOT EXISTS "feature_notification_outbox_unprocessed_idx" ON "public"."feature_notification_outbox" USING "btree" ("created_at") WHERE ("processed_at" IS NULL);

CREATE INDEX IF NOT EXISTS "feature_requests_category_idx" ON "public"."feature_requests" USING "btree" ("category");

CREATE INDEX IF NOT EXISTS "feature_requests_listing_idx" ON "public"."feature_requests" USING "btree" ("is_pinned" DESC, "upvote_count" DESC);

CREATE INDEX IF NOT EXISTS "feature_requests_status_idx" ON "public"."feature_requests" USING "btree" ("status");

CREATE INDEX IF NOT EXISTS "feature_requests_title_trgm_idx" ON "public"."feature_requests" USING "gin" ("title" "public"."gin_trgm_ops");

CREATE INDEX IF NOT EXISTS "feature_votes_created_at_idx" ON "public"."feature_votes" USING "btree" ("created_at");

CREATE INDEX IF NOT EXISTS "feature_votes_user_id_idx" ON "public"."feature_votes" USING "btree" ("user_id");


-- ---------------------------------------------------------------------------
-- Functions and triggers
-- ---------------------------------------------------------------------------
--
-- Verbatim from production. `create or replace` makes both idempotent.

CREATE OR REPLACE FUNCTION "public"."enforce_feature_request_owner_edit_scope"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if public.is_feedback_admin() or pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.status is distinct from old.status
    or new.is_pinned is distinct from old.is_pinned
    or new.merged_into is distinct from old.merged_into
    or new.author_id is distinct from old.author_id
    or new.slug is distinct from old.slug
    or new.upvote_count is distinct from old.upvote_count
    or new.comment_count is distinct from old.comment_count
  then
    raise exception 'Only admins can change status, pin, merge, author, slug, or counts on a feature request.';
  end if;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."enqueue_developer_update_notifications"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.feature_notification_outbox (feature_id, event_type, recipient_id, payload)
  select
    new.feature_id,
    'developer_update_posted',
    recipient_id,
    jsonb_build_object('update_body', new.body)
  from (
    select user_id as recipient_id from public.feature_votes where feature_id = new.feature_id
    union
    select user_id as recipient_id from public.feature_subscribers where feature_id = new.feature_id
  ) recipients;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."enqueue_feature_status_change_notifications"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.feature_notification_outbox (feature_id, event_type, recipient_id, payload)
  select
    new.id,
    'status_changed',
    recipient_id,
    jsonb_build_object(
      'feature_title', new.title,
      'feature_slug', new.slug,
      'old_status', old.status,
      'new_status', new.status
    )
  from (
    select user_id as recipient_id from public.feature_votes where feature_id = new.id
    union
    select user_id as recipient_id from public.feature_subscribers where feature_id = new.id
  ) recipients;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."get_feedback_public_profiles"("profile_ids" "uuid"[]) RETURNS TABLE("id" "uuid", "display_name" "text", "avatar_path" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select p.id, coalesce(nullif(p.first_name, ''), 'Twofold user') as display_name, p.avatar_path
  from public.profiles p
  where p.id = any(profile_ids);
$$;

CREATE OR REPLACE FUNCTION "public"."merge_feature_requests"("source_id" "uuid", "target_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_feedback_admin() then
    raise exception 'Only admins can merge feature requests.';
  end if;

  if source_id = target_id then
    raise exception 'Cannot merge a feature request into itself.';
  end if;

  -- Re-point votes that don't already exist on the target (a user can't hold two votes
  -- on what's about to become the same feature); drop the rest.
  update public.feature_votes v
  set feature_id = target_id
  where v.feature_id = source_id
    and not exists (
      select 1 from public.feature_votes existing
      where existing.feature_id = target_id and existing.user_id = v.user_id
    );

  delete from public.feature_votes where feature_id = source_id;

  -- All comments carry over — no uniqueness concern like votes have.
  update public.feature_comments set feature_id = target_id where feature_id = source_id;

  -- Bulk UPDATEs above don't fire the per-row count-sync triggers (those only run on
  -- INSERT/DELETE against feature_votes/feature_comments directly), so recompute both
  -- features' counts explicitly instead of trusting the triggers here.
  update public.feature_requests
  set upvote_count = (select count(*) from public.feature_votes where feature_id = target_id),
      comment_count = (select count(*) from public.feature_comments where feature_id = target_id)
  where id = target_id;

  update public.feature_requests
  set status = 'closed',
      merged_into = target_id,
      upvote_count = 0,
      comment_count = 0
  where id = source_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."popular_this_week"("result_limit" integer DEFAULT 5) RETURNS TABLE("id" "uuid", "title" "text", "slug" "text", "status" "public"."feedback_request_status", "upvote_count" integer, "recent_votes" bigint)
    LANGUAGE "sql" STABLE
    AS $$
  select fr.id, fr.title, fr.slug, fr.status, fr.upvote_count, v.recent_votes
  from public.feature_requests fr
  join (
    select feature_id, count(*) as recent_votes
    from public.feature_votes
    where created_at >= now() - interval '7 days'
    group by feature_id
  ) v on v.feature_id = fr.id
  where fr.merged_into is null
  order by v.recent_votes desc
  limit result_limit;
$$;

CREATE OR REPLACE FUNCTION "public"."search_similar_feature_requests"("query" "text", "match_limit" integer DEFAULT 5) RETURNS TABLE("id" "uuid", "title" "text", "slug" "text", "upvote_count" integer, "status" "public"."feedback_request_status", "similarity" real)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select
    id, title, slug, upvote_count, status,
    similarity(title, query) as similarity
  from public.feature_requests
  where merged_into is null
    and similarity(title, query) > 0.2
  order by similarity(title, query) desc
  limit match_limit;
$$;

CREATE OR REPLACE FUNCTION "public"."sync_feature_comment_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if tg_op = 'INSERT' then
    update public.feature_requests set comment_count = comment_count + 1 where id = new.feature_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.feature_requests set comment_count = greatest(comment_count - 1, 0) where id = old.feature_id;
    return old;
  end if;
  return null;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."sync_feature_upvote_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if tg_op = 'INSERT' then
    update public.feature_requests set upvote_count = upvote_count + 1 where id = new.feature_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.feature_requests set upvote_count = greatest(upvote_count - 1, 0) where id = old.feature_id;
    return old;
  end if;
  return null;
end;
$$;

CREATE OR REPLACE TRIGGER "trg_developer_updates_notify" AFTER INSERT ON "public"."developer_updates" FOR EACH ROW EXECUTE FUNCTION "public"."enqueue_developer_update_notifications"();

CREATE OR REPLACE TRIGGER "trg_feature_comments_sync_count" AFTER INSERT OR DELETE ON "public"."feature_comments" FOR EACH ROW EXECUTE FUNCTION "public"."sync_feature_comment_count"();

CREATE OR REPLACE TRIGGER "trg_feature_comments_touch" BEFORE UPDATE ON "public"."feature_comments" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();

CREATE OR REPLACE TRIGGER "trg_feature_requests_owner_edit_scope" BEFORE UPDATE ON "public"."feature_requests" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_feature_request_owner_edit_scope"();

CREATE OR REPLACE TRIGGER "trg_feature_requests_status_change_notify" AFTER UPDATE OF "status" ON "public"."feature_requests" FOR EACH ROW WHEN (("old"."status" IS DISTINCT FROM "new"."status")) EXECUTE FUNCTION "public"."enqueue_feature_status_change_notifications"();

CREATE OR REPLACE TRIGGER "trg_feature_requests_touch" BEFORE UPDATE ON "public"."feature_requests" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();

CREATE OR REPLACE TRIGGER "trg_feature_votes_sync_count" AFTER INSERT OR DELETE ON "public"."feature_votes" FOR EACH ROW EXECUTE FUNCTION "public"."sync_feature_upvote_count"();


-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
--
-- Each policy is dropped first, so re-applying replaces rather than erroring on a duplicate
-- name — and so a policy edited by hand in the dashboard is brought back to what is written here.

ALTER TABLE "public"."developer_updates" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."feature_bookmarks" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."feature_comments" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."feature_notification_outbox" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."feature_requests" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."feature_subscribers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."feature_votes" ENABLE ROW LEVEL SECURITY;

drop policy if exists "developer_updates_delete_admin" on "public"."developer_updates";
CREATE POLICY "developer_updates_delete_admin" ON "public"."developer_updates" FOR DELETE USING ("public"."is_feedback_admin"());

drop policy if exists "developer_updates_insert_admin" on "public"."developer_updates";
CREATE POLICY "developer_updates_insert_admin" ON "public"."developer_updates" FOR INSERT WITH CHECK ("public"."is_feedback_admin"());

drop policy if exists "developer_updates_select_all" on "public"."developer_updates";
CREATE POLICY "developer_updates_select_all" ON "public"."developer_updates" FOR SELECT USING (true);

drop policy if exists "developer_updates_update_admin" on "public"."developer_updates";
CREATE POLICY "developer_updates_update_admin" ON "public"."developer_updates" FOR UPDATE USING ("public"."is_feedback_admin"()) WITH CHECK ("public"."is_feedback_admin"());

drop policy if exists "feature_bookmarks_delete_own" on "public"."feature_bookmarks";
CREATE POLICY "feature_bookmarks_delete_own" ON "public"."feature_bookmarks" FOR DELETE USING (("user_id" = "auth"."uid"()));

drop policy if exists "feature_bookmarks_insert_own" on "public"."feature_bookmarks";
CREATE POLICY "feature_bookmarks_insert_own" ON "public"."feature_bookmarks" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));

drop policy if exists "feature_bookmarks_select_own" on "public"."feature_bookmarks";
CREATE POLICY "feature_bookmarks_select_own" ON "public"."feature_bookmarks" FOR SELECT USING (("user_id" = "auth"."uid"()));

drop policy if exists "feature_comments_delete_own_or_admin" on "public"."feature_comments";
CREATE POLICY "feature_comments_delete_own_or_admin" ON "public"."feature_comments" FOR DELETE USING ((("user_id" = "auth"."uid"()) OR "public"."is_feedback_admin"()));

drop policy if exists "feature_comments_insert_own" on "public"."feature_comments";
CREATE POLICY "feature_comments_insert_own" ON "public"."feature_comments" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));

drop policy if exists "feature_comments_select_all" on "public"."feature_comments";
CREATE POLICY "feature_comments_select_all" ON "public"."feature_comments" FOR SELECT USING (true);

drop policy if exists "feature_comments_update_own" on "public"."feature_comments";
CREATE POLICY "feature_comments_update_own" ON "public"."feature_comments" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));

drop policy if exists "feature_requests_delete_admin" on "public"."feature_requests";
CREATE POLICY "feature_requests_delete_admin" ON "public"."feature_requests" FOR DELETE USING ("public"."is_feedback_admin"());

drop policy if exists "feature_requests_insert_own" on "public"."feature_requests";
CREATE POLICY "feature_requests_insert_own" ON "public"."feature_requests" FOR INSERT WITH CHECK (("author_id" = "auth"."uid"()));

drop policy if exists "feature_requests_select_all" on "public"."feature_requests";
CREATE POLICY "feature_requests_select_all" ON "public"."feature_requests" FOR SELECT USING (true);

drop policy if exists "feature_requests_update_admin" on "public"."feature_requests";
CREATE POLICY "feature_requests_update_admin" ON "public"."feature_requests" FOR UPDATE USING ("public"."is_feedback_admin"()) WITH CHECK ("public"."is_feedback_admin"());

drop policy if exists "feature_requests_update_own_recent" on "public"."feature_requests";
CREATE POLICY "feature_requests_update_own_recent" ON "public"."feature_requests" FOR UPDATE USING ((("author_id" = "auth"."uid"()) AND ("created_at" > ("now"() - '00:15:00'::interval)))) WITH CHECK (("author_id" = "auth"."uid"()));

drop policy if exists "feature_subscribers_delete_own" on "public"."feature_subscribers";
CREATE POLICY "feature_subscribers_delete_own" ON "public"."feature_subscribers" FOR DELETE USING (("user_id" = "auth"."uid"()));

drop policy if exists "feature_subscribers_insert_own" on "public"."feature_subscribers";
CREATE POLICY "feature_subscribers_insert_own" ON "public"."feature_subscribers" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));

drop policy if exists "feature_subscribers_select_own_or_admin" on "public"."feature_subscribers";
CREATE POLICY "feature_subscribers_select_own_or_admin" ON "public"."feature_subscribers" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_feedback_admin"()));

drop policy if exists "feature_votes_delete_own" on "public"."feature_votes";
CREATE POLICY "feature_votes_delete_own" ON "public"."feature_votes" FOR DELETE USING (("user_id" = "auth"."uid"()));

drop policy if exists "feature_votes_insert_own" on "public"."feature_votes";
CREATE POLICY "feature_votes_insert_own" ON "public"."feature_votes" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));

drop policy if exists "feature_votes_select_all" on "public"."feature_votes";
CREATE POLICY "feature_votes_select_all" ON "public"."feature_votes" FOR SELECT USING (true);


-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
--
-- Idempotent as written.

GRANT ALL ON FUNCTION "public"."enforce_feature_request_owner_edit_scope"() TO "anon";

GRANT ALL ON FUNCTION "public"."enforce_feature_request_owner_edit_scope"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."enforce_feature_request_owner_edit_scope"() TO "service_role";

GRANT ALL ON FUNCTION "public"."enqueue_developer_update_notifications"() TO "anon";

GRANT ALL ON FUNCTION "public"."enqueue_developer_update_notifications"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."enqueue_developer_update_notifications"() TO "service_role";

GRANT ALL ON FUNCTION "public"."enqueue_feature_status_change_notifications"() TO "anon";

GRANT ALL ON FUNCTION "public"."enqueue_feature_status_change_notifications"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."enqueue_feature_status_change_notifications"() TO "service_role";

GRANT ALL ON FUNCTION "public"."get_feedback_public_profiles"("profile_ids" "uuid"[]) TO "anon";

GRANT ALL ON FUNCTION "public"."get_feedback_public_profiles"("profile_ids" "uuid"[]) TO "authenticated";

GRANT ALL ON FUNCTION "public"."get_feedback_public_profiles"("profile_ids" "uuid"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."merge_feature_requests"("source_id" "uuid", "target_id" "uuid") TO "anon";

GRANT ALL ON FUNCTION "public"."merge_feature_requests"("source_id" "uuid", "target_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."merge_feature_requests"("source_id" "uuid", "target_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."popular_this_week"("result_limit" integer) TO "anon";

GRANT ALL ON FUNCTION "public"."popular_this_week"("result_limit" integer) TO "authenticated";

GRANT ALL ON FUNCTION "public"."popular_this_week"("result_limit" integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."search_similar_feature_requests"("query" "text", "match_limit" integer) TO "anon";

GRANT ALL ON FUNCTION "public"."search_similar_feature_requests"("query" "text", "match_limit" integer) TO "authenticated";

GRANT ALL ON FUNCTION "public"."search_similar_feature_requests"("query" "text", "match_limit" integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."sync_feature_comment_count"() TO "anon";

GRANT ALL ON FUNCTION "public"."sync_feature_comment_count"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."sync_feature_comment_count"() TO "service_role";

GRANT ALL ON FUNCTION "public"."sync_feature_upvote_count"() TO "anon";

GRANT ALL ON FUNCTION "public"."sync_feature_upvote_count"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."sync_feature_upvote_count"() TO "service_role";

GRANT ALL ON TABLE "public"."developer_updates" TO "anon";

GRANT ALL ON TABLE "public"."developer_updates" TO "authenticated";

GRANT ALL ON TABLE "public"."developer_updates" TO "service_role";

GRANT ALL ON TABLE "public"."feature_bookmarks" TO "anon";

GRANT ALL ON TABLE "public"."feature_bookmarks" TO "authenticated";

GRANT ALL ON TABLE "public"."feature_bookmarks" TO "service_role";

GRANT ALL ON TABLE "public"."feature_comments" TO "anon";

GRANT ALL ON TABLE "public"."feature_comments" TO "authenticated";

GRANT ALL ON TABLE "public"."feature_comments" TO "service_role";

GRANT ALL ON TABLE "public"."feature_notification_outbox" TO "anon";

GRANT ALL ON TABLE "public"."feature_notification_outbox" TO "authenticated";

GRANT ALL ON TABLE "public"."feature_notification_outbox" TO "service_role";

GRANT ALL ON TABLE "public"."feature_requests" TO "anon";

GRANT ALL ON TABLE "public"."feature_requests" TO "authenticated";

GRANT ALL ON TABLE "public"."feature_requests" TO "service_role";

GRANT ALL ON TABLE "public"."feature_subscribers" TO "anon";

GRANT ALL ON TABLE "public"."feature_subscribers" TO "authenticated";

GRANT ALL ON TABLE "public"."feature_subscribers" TO "service_role";

GRANT ALL ON TABLE "public"."feature_votes" TO "anon";

GRANT ALL ON TABLE "public"."feature_votes" TO "authenticated";

GRANT ALL ON TABLE "public"."feature_votes" TO "service_role";
