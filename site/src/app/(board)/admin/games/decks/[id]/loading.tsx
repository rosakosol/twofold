import { Skeleton } from "@/components/ui/skeleton";

/** Back-link + deck header + entry table stand-in — see ../../[type]/decks/loading.tsx. */
export default function Loading() {
  return (
    <div>
      <Skeleton className="h-5 w-32" />
      <Skeleton className="mt-4 h-24 w-full rounded-lg" />
      <Skeleton className="mt-6 h-64 w-full rounded-lg" />
    </div>
  );
}
