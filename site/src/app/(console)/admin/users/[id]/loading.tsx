import { Skeleton } from "@/components/ui/skeleton";

/// App Router shows the previous page untouched until a server component resolves. On a route that
/// makes several Supabase round-trips that is long enough to read as a dead link, and a dead link
/// gets clicked again.
export default function Loading() {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Skeleton className="h-7 w-40" />
        <Skeleton className="h-4 w-56" />
      </div>
      <Skeleton className="h-64 w-full rounded-lg" />
    </div>
  );
}
