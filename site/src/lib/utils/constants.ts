// Mirrors the DB enums public.feedback_request_status / public.feedback_request_category
// (repo-root supabase/migrations/20261109000600_feedback_board_schema.sql) — keep these in sync if the
// enum ever changes.

export const STATUS_VALUES = [
  "requested",
  "considering",
  "planned",
  "in_progress",
  "released",
  "closed",
] as const;

export type FeatureStatus = (typeof STATUS_VALUES)[number];

export const STATUS_LABELS: Record<FeatureStatus, string> = {
  requested: "Requested",
  considering: "Considering",
  planned: "Planned",
  in_progress: "In progress",
  // The enum value stays `released`; what people read is "Shipped", the same word the roadmap uses.
  released: "Shipped",
  closed: "Closed",
};

// Order used for the roadmap kanban board — "closed" is deliberately excluded from the
// roadmap (it's not a forward-looking state), but still a valid request status.
export const ROADMAP_STATUSES: FeatureStatus[] = [
  "requested",
  "considering",
  "planned",
  "in_progress",
  "released",
];

export const CATEGORY_VALUES = [
  "flights",
  "memories",
  "games",
  "widgets",
  "notifications",
  "relationship",
  "general",
] as const;

export type FeatureCategory = (typeof CATEGORY_VALUES)[number];

export const CATEGORY_LABELS: Record<FeatureCategory, string> = {
  flights: "Flights",
  memories: "Memories",
  games: "Games",
  widgets: "Widgets",
  notifications: "Notifications",
  relationship: "Relationship",
  general: "General",
};
