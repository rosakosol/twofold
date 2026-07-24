export const queryKeys = {
  feature: (slug: string) => ["features", "detail", slug] as const,
  comments: (featureId: string) => ["features", featureId, "comments"] as const,
  myVotes: (userId: string | undefined) => ["votes", "mine", userId] as const,
  myBookmarks: (userId: string | undefined) => ["bookmarks", "mine", userId] as const,
  mySubscriptions: (userId: string | undefined) => ["subscriptions", "mine", userId] as const,
  duplicateSearch: (query: string) => ["features", "duplicates", query] as const,
  roadmap: () => ["features", "roadmap"] as const,
  adminFeatureList: (filters: unknown) => ["admin", "features", filters] as const,
};
