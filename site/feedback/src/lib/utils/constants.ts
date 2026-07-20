// Mirrors the DB enums public.feedback_request_status / public.feedback_request_category
// (supabase/migrations/20260719000100_feedback_enums.sql) — keep these in sync if the
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
  in_progress: "In Progress",
  released: "Released",
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

export type SortOption = "top" | "new" | "recently_updated";

export const SORT_LABELS: Record<SortOption, string> = {
  top: "Most Upvoted",
  new: "Newest",
  recently_updated: "Recently Updated",
};
