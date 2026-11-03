export const queryKeys = {
  myVotes: (userId: string | undefined) => ["votes", "mine", userId] as const,
  duplicateSearch: (query: string) => ["features", "duplicates", query] as const,
  roadmap: () => ["features", "roadmap"] as const,
  adminFeatureList: (filters: unknown) => ["admin", "features", filters] as const,
};
