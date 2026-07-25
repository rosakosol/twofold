import { Skeleton } from "@/components/ui/skeleton";

/** Stands in for the back-link + heading + DeckTable while this segment renders.
 * Note this only buys you anything once the route is compiled (i.e. production, or dev
 * after the first visit) — in dev the very first click waits on Turbopack before the
 * server sends any bytes at all, which is what scripts/warm-dev.mjs pre-empts. */
export default function Loading() {
  return (
    <div>
      <Skeleton className="h-5 w-32" />
      <Skeleton className="mt-4 h-7 w-56" />
      <Skeleton className="mt-6 h-64 w-full rounded-lg" />
    </div>
  );
}
