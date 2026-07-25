import { Skeleton } from "@/components/ui/skeleton";

/** Instant-loading boundary for the whole /admin segment. Without it, clicking "Admin"
 * leaves you on the previous page until AdminLayout's `isFeedbackAdmin()` round-trip AND
 * the page render both finish — the click reads as ignored. loading.tsx is the fallback
 * the parent renders for this segment, so the layout's await happens behind this skeleton
 * and the URL/page swap immediately. Mirrors admin/page.tsx's shape (heading, filter row,
 * table) so the swap to real content doesn't jump. */
export default function Loading() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-6 flex items-center justify-between border-b pb-3">
        <Skeleton className="h-8 w-24 rounded-md" />
      </div>
      <Skeleton className="h-7 w-32" />
      <Skeleton className="mt-2 h-4 w-48" />
      <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center">
        <Skeleton className="h-9 w-full rounded-full sm:max-w-xs sm:flex-1" />
        <Skeleton className="h-8 w-36 rounded-md" />
        <Skeleton className="h-8 w-36 rounded-md" />
      </div>
      <Skeleton className="mt-6 h-64 w-full rounded-lg" />
    </div>
  );
}
