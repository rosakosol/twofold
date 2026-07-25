import { Skeleton } from "@/components/ui/skeleton";

/** Back-link + heading + ContentTable stand-in — see the sibling decks/loading.tsx. */
export default function Loading() {
  return (
    <div>
      <Skeleton className="h-5 w-32" />
      <Skeleton className="mt-4 h-7 w-64" />
      <Skeleton className="mt-6 h-64 w-full rounded-lg" />
    </div>
  );
}
