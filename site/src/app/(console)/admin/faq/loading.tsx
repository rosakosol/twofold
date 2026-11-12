import { Skeleton } from "@/components/ui/skeleton";

/** Stands in for the heading and the question list while /admin/faq loads. */
export default function Loading() {
  return (
    <div>
      <Skeleton className="h-7 w-24" />
      <Skeleton className="mt-2 h-4 w-96 max-w-full" />
      <Skeleton className="mt-6 h-64 w-full rounded-lg" />
    </div>
  );
}
