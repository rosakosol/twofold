import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { slugify, randomSlugSuffix } from "@/lib/utils/slug";
import type { CreateFeatureRequestInput } from "@/lib/validation/feature";

export function useCreateFeature() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ input, userId }: { input: CreateFeatureRequestInput; userId: string }) => {
      const supabase = createClient();
      const baseSlug = slugify(input.title) || "request";

      // Retries with a random suffix on a slug collision only — any other failure
      // (RLS rejection, network error, etc.) throws immediately.
      for (let attempt = 0; attempt < 5; attempt++) {
        const slug = attempt === 0 ? baseSlug : `${baseSlug}-${randomSlugSuffix()}`;
        const { data, error } = await supabase
          .from("feature_requests")
          .insert({
            title: input.title,
            description: input.description,
            category: input.category,
            author_id: userId,
            slug,
          })
          .select()
          .single();

        if (!error) return data;
        if (error.code !== "23505") throw error; // not a unique_violation — don't retry
      }

      throw new Error("Couldn't generate a unique slug after several attempts.");
    },
    onSuccess: () => {
      // "list" (the old infinite-scroll query) and "roadmap" (what the board's flat
      // list + roadmap sections actually render from) both need invalidating so a new
      // request shows up immediately without a manual refresh.
      queryClient.invalidateQueries({ queryKey: ["features", "list"] });
      queryClient.invalidateQueries({ queryKey: ["features", "roadmap"] });
    },
  });
}
