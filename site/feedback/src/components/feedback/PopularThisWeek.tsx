import Link from "next/link";
import { TrendingUp } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { FeatureStatusBadge } from "@/components/feedback/FeatureStatusBadge";
import { usePopularThisWeek } from "@/lib/queries/usePopularThisWeek";
import type { FeatureStatus } from "@/lib/utils/constants";

export function PopularThisWeek() {
  const { data, isLoading } = usePopularThisWeek();

  if (isLoading) {
    return (
      <div className="rounded-xl border bg-card p-4">
        <Skeleton className="h-4 w-32" />
        <div className="mt-3 space-y-2">
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-full" />
        </div>
      </div>
    );
  }

  if (!data || data.length === 0) return null;

  return (
    <div className="rounded-xl border bg-card p-4">
      <div className="flex items-center gap-1.5 text-sm font-semibold">
        <TrendingUp className="h-4 w-4 text-primary" />
        Popular this week
      </div>
      <ul className="mt-3 space-y-1">
        {data.map((item) => (
          <li key={item.id}>
            <Link
              href={`/feedback/${item.slug}`}
              className="flex items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-sm hover:bg-accent/40"
            >
              <span className="truncate">{item.title}</span>
              <FeatureStatusBadge status={item.status as FeatureStatus} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
