import { Skeleton } from "@/components/ui/skeleton";

/** Same instant-transition purpose as admin/loading.tsx, scoped to /admin/games — the
 * admin layout/nav is already on screen by the time you click "Games", so this only
 * stands in for the heading + tab strip + tab body. */
export default function Loading() {
  return (
    <div>
      <Skeleton className="h-7 w-24" />
      <Skeleton className="mt-2 h-4 w-96 max-w-full" />
      <div className="mt-6 flex flex-wrap gap-1">
        {Array.from({ length: 6 }).map((_, i) => (
          <Skeleton key={i} className="h-8 w-28 rounded-md" />
        ))}
      </div>
      <Skeleton className="mt-4 h-40 w-full rounded-lg" />
    </div>
  );
}
