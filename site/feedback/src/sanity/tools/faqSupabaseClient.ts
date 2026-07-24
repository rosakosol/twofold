import { createClient } from "@supabase/supabase-js";

// Deliberately a plain, untyped client (not lib/supabase/client.ts's `Database`-typed one) —
// faq_entries belongs to the main Twofold app's schema, not this feedback board's own generated
// types, and this tool is the only place in this project reading/writing it.
export const faqSupabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

export interface FaqEntryRow {
  id: string;
  category: string | null;
  question: string;
  answer: string;
  sort_order: number;
  created_at: string;
}
