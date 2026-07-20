-- Feedback board: enums for feature_requests, created up front so later migrations in
-- this folder can reference them. Namespaced (feedback_request_*, not generic
-- status/category) to avoid any future name collision in the shared `public` schema —
-- this project's migrations run alongside the main app's (see repo-root
-- supabase/migrations/), which we never touch directly from here.

create extension if not exists pg_trgm;
-- Idempotent: the main app's migrations already enable this (see
-- supabase/migrations/20260708102734_phase1_core_schema.sql), but this folder's
-- migrations shouldn't assume that stays true forever.

create type public.feedback_request_status as enum (
  'requested',
  'considering',
  'planned',
  'in_progress',
  'released',
  'closed'
);

create type public.feedback_request_category as enum (
  'flights',
  'memories',
  'games',
  'widgets',
  'notifications',
  'relationship',
  'general'
);
