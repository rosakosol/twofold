// FAQ content lives in the main Twofold app's Supabase project (`faq_entries` table) — shared
// with the iOS app's Settings > Support screen, and edited via the Studio's custom FAQ tool
// (src/sanity/tools/FaqTool.tsx) rather than Sanity's own dataset. A public SELECT policy on
// that table makes this a plain anon-key REST read, no auth/service-role needed. Replaces the
// old Sanity `faqItem` document type + getFaqItems() (see sanity.ts's history).

export const FAQ_REVALIDATE_SECONDS = 60;

export interface FaqEntry {
  id: string;
  category: string | null;
  question: string;
  answer: string;
  sortOrder: number;
}

interface FaqEntryRow {
  id: string;
  category: string | null;
  question: string;
  answer: string;
  sort_order: number;
}

// Never throws — a Supabase outage should fall back to static copy (see faqFallback.ts), not a
// broken /faq page. Returns [] on any failure; callers treat that as "use the fallback."
export async function getFaqEntries(): Promise<FaqEntry[]> {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!baseUrl || !anonKey) return [];

  try {
    const res = await fetch(
      `${baseUrl}/rest/v1/faq_entries?select=id,category,question,answer,sort_order&order=sort_order.asc`,
      {
        headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}` },
        next: { revalidate: FAQ_REVALIDATE_SECONDS },
      }
    );
    if (!res.ok) return [];
    const rows: FaqEntryRow[] = await res.json();
    return rows.map((row) => ({
      id: row.id,
      category: row.category,
      question: row.question,
      answer: row.answer,
      sortOrder: row.sort_order,
    }));
  } catch {
    return [];
  }
}

export interface FaqGroup {
  category: string;
  items: FaqEntry[];
}

// Groups are ordered by their first (lowest-sortOrder) entry — same convention the iOS app's
// SupportView.swift uses — so category order is controlled entirely by each row's own
// sort_order, no separate category-ordering column needed.
export function groupFaqEntriesByCategory(entries: FaqEntry[]): FaqGroup[] {
  const byCategory = new Map<string, FaqEntry[]>();
  for (const entry of entries) {
    const key = entry.category ?? "General";
    const list = byCategory.get(key);
    if (list) list.push(entry);
    else byCategory.set(key, [entry]);
  }
  return Array.from(byCategory.entries())
    .map(([category, items]) => ({ category, items }))
    .sort((a, b) => (a.items[0]?.sortOrder ?? Number.MAX_SAFE_INTEGER) - (b.items[0]?.sortOrder ?? Number.MAX_SAFE_INTEGER));
}
