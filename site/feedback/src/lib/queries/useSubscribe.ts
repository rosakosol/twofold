import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";

export function useIsSubscribed(featureId: string, userId: string | undefined) {
  return useQuery({
    queryKey: ["subscriptions", featureId, userId],
    enabled: !!userId,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_subscribers")
        .select("feature_id")
        .eq("feature_id", featureId)
        .eq("user_id", userId!)
        .maybeSingle();
      if (error) throw error;
      return !!data;
    },
  });
}

export function useToggleSubscribe(featureId: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ userId, isSubscribed }: { userId: string; isSubscribed: boolean }) => {
      const supabase = createClient();
      if (isSubscribed) {
        const { error } = await supabase
          .from("feature_subscribers")
          .delete()
          .eq("feature_id", featureId)
          .eq("user_id", userId);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("feature_subscribers")
          .insert({ feature_id: featureId, user_id: userId });
        if (error) throw error;
      }
    },
    onSuccess: (_data, { userId }) => {
      queryClient.invalidateQueries({ queryKey: ["subscriptions", featureId, userId] });
      queryClient.invalidateQueries({ queryKey: queryKeys.mySubscriptions(userId) });
    },
  });
}
