import type { FeatureListItem } from "@/lib/queries/useFeatureList";

// Still used by the admin request table/edit flow (useAdminFeatures.ts,
// AdminFeatureTable.tsx) — the public detail page that originally owned this select
// was removed, but admin needs the same full row shape.
export const FEATURE_DETAIL_SELECT = `
  id, title, slug, description, category, status, upvote_count, comment_count,
  is_pinned, merged_into, created_at, updated_at, author_id,
  author:feedback_public_profiles!feature_requests_author_id_fkey(id, display_name, avatar_path)
`;

export type FeatureDetail = FeatureListItem;
