import { createBrowserClient } from "@supabase/ssr";

// Deliberately untyped (not lib/supabase/client.ts's `Database`-typed client) — faq_entries
// belongs to the main Twofold app's schema, not this feedback board's own generated types, and
// this tool is the only place in this project reading or writing it.
//
// `createBrowserClient` rather than a plain anon `createClient`: it reads the same auth cookies the
// site's middleware maintains, so requests carry the signed-in user's session. Reads do not need
// that (faq_entries is publicly readable) but writes do — they go straight to the table now, under
// the `faq_entries_admin_write` policy, instead of through an Edge Function holding a shared secret
// that shipped inside a public JS bundle. Same client for both, so a signed-out editor fails on the
// write rather than silently reading as anon and writing as nobody.
export const faqSupabase = createBrowserClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

export interface FaqEntryRow {
  id: string;
  category: string | null;
  question: string;
  answer: string;
  sort_order: number;
  created_at: string;
}
