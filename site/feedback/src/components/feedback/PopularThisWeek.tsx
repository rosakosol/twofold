import { TrendingUp } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { FeatureStatusBadge } from "@/components/feedback/FeatureStatusBadge";
import { usePopularThisWeek } from "@/lib/queries/usePopularThisWeek";
import type { FeatureStatus } from "@/lib/utils/constants";

export function PopularThisWeek() {
  const { data, isLoading } = usePopularThisWeek();

  if (isLoading) {
    return (
      <div className="rounded-xl bg-card p-4 shadow-sm">
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
    <div className="rounded-xl bg-card p-4 shadow-sm">
      <div className="flex items-center gap-1.5 text-sm font-semibold">
        <TrendingUp className="h-4 w-4 text-primary" />
        Popular this week
      </div>
      <ul className="mt-3 space-y-1">
        {data.map((item) => (
          <li
            key={item.id}
            className="flex items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-sm"
          >
            <span className="truncate">{item.title}</span>
            <FeatureStatusBadge status={item.status as FeatureStatus} />
          </li>
        ))}
      </ul>
    </div>
  );
}
