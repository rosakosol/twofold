// This file used to also export useInfiniteFeatureList, a scroll-triggered query
// for the main board — removed as dead code once the feedback board's redesign
// (matching site/design_handoff_twofold_site) switched the board to useRoadmap's
// single fetch instead. FeatureListItem stays: useBookmarks.ts and useAdminFeatures.ts
// (as FeatureDetail) still shape their rows this way.
export interface FeatureListItem {
  id: string;
  title: string;
  slug: string;
  description: string;
  category: string;
  status: string;
  upvote_count: number;
  comment_count: number;
  is_pinned: boolean;
  merged_into: string | null;
  created_at: string;
  updated_at: string;
  author_id: string | null;
  author: { id: string; display_name: string; avatar_path: string | null } | null;
}
