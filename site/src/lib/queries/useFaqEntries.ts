import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/lib/db/types";
import { requireChanged } from "@/lib/supabase/dbError";

/**
 * The FAQ, edited from the console (/admin/faq).
 *
 * `faq_entries` is the one FAQ for both the website's /faq page and the iOS app's Settings > Support
 * screen. It used to be edited from a custom tool inside Sanity Studio, which meant Studio carried
 * a Supabase admin session on the same origin as the console. Editing it here keeps the admin
 * session in one place, behind the console's sign-in code and its strict CSP, and lets Studio live
 * on Sanity's own hosting with no Supabase access at all.
 *
 * Writes go to the table as the signed-in admin, under the `faq_entries_admin_write` policy
 * (`is_feedback_admin()`, the content role, at aal2). Updates and deletes ask for an exact count,
 * because one RLS filters out answers 2xx having changed nothing (see dbError.ts).
 */

export type FaqEntryRow = Database["public"]["Tables"]["faq_entries"]["Row"];
type FaqInsert = Database["public"]["Tables"]["faq_entries"]["Insert"];
type FaqUpdate = Database["public"]["Tables"]["faq_entries"]["Update"];

const FAQ_KEY = ["admin", "faq_entries"] as const;

export function useFaqEntries() {
  return useQuery({
    queryKey: FAQ_KEY,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("faq_entries")
        .select("*")
        .order("sort_order")
        .order("created_at");
      if (error) throw error;
      return data;
    },
  });
}

export function useCreateFaqEntry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (row: FaqInsert) => {
      const supabase = createClient();
      requireChanged(await supabase.from("faq_entries").insert(row, { count: "exact" }), "entry");
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: FAQ_KEY }),
  });
}

export function useUpdateFaqEntry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: FaqUpdate }) => {
      const supabase = createClient();
      requireChanged(await supabase.from("faq_entries").update(patch, { count: "exact" }).eq("id", id), "entry");
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: FAQ_KEY }),
  });
}

export function useDeleteFaqEntry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      requireChanged(await supabase.from("faq_entries").delete({ count: "exact" }).eq("id", id), "entry");
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: FAQ_KEY }),
  });
}
