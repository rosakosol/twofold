import type { FeatureListItem } from "@/lib/queries/useFeatureList";

// Still used by the admin request table/edit flow (useAdminFeatures.ts,
// AdminFeatureTable.tsx) — the public detail page that originally owned this select
// was removed, but admin needs the same full row shape. Deliberately doesn't select
// an author profile at all: admin never displays it (the old author:
// feedback_public_profiles!... embed here was unused dead weight), so there's no
// reason to spend the extra get_feedback_public_profiles round trip for these rows —
// see useAdminFeatures.ts, which fills `author: null` in to satisfy FeatureDetail's
// (aka FeatureListItem's) shape instead.
export const FEATURE_DETAIL_SELECT = `
  id, title, slug, description, category, status, upvote_count, comment_count,
  is_pinned, merged_into, created_at, updated_at, author_id
`;

export type FeatureDetail = FeatureListItem;
