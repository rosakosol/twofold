import { Skeleton } from "@/components/ui/skeleton";

/// Without this, a navigation to /account shows nothing at all until the server has finished —
/// the browser stays on the previous page with no indication anything is happening, which is how
/// somebody ends up clicking the link again and starting the whole thing over.
export default function Loading() {
  return (
    <div className="space-y-8">
      <div className="space-y-2">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-4 w-64" />
      </div>
      <Skeleton className="h-52 w-full rounded-xl" />
      <Skeleton className="h-40 w-full rounded-xl" />
      <Skeleton className="h-72 w-full rounded-xl" />
    </div>
  );
}
