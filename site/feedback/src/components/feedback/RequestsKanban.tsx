import Link from "next/link";
import { ChevronUp, MessageSquare } from "lucide-react";
import { CategoryBadge } from "@/components/feedback/CategoryBadge";
import type { FeatureCategory, FeatureStatus } from "@/lib/utils/constants";
import type { RoadmapItem } from "@/lib/queries/useRoadmap";

interface Bucket {
  key: string;
  label: string;
  statuses: FeatureStatus[];
}

/** Merges the fuller 6-stage pipeline into 3 quick-glance buckets — the detailed
 * per-stage breakdown still lives in the Roadmap section below this one. */
const BUCKETS: Bucket[] = [
  { key: "requested", label: "Requested", statuses: ["requested", "considering"] },
  { key: "planned", label: "Planned", statuses: ["planned", "in_progress"] },
  { key: "shipped", label: "Shipped", statuses: ["released"] },
];

function SummaryColumn({ label, items }: { label: string; items: RoadmapItem[] }) {
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-3">
      <div className="flex items-center gap-2 px-1">
        <h3 className="text-sm font-semibold">{label}</h3>
        <span className="text-xs text-muted-foreground">{items.length}</span>
      </div>

      <div className="flex flex-col gap-2">
        {items.length === 0 ? (
          <p className="rounded-lg border border-dashed px-3 py-6 text-center text-xs text-muted-foreground">
            Nothing here yet
          </p>
        ) : (
          items.map((item) => (
            <Link
              key={item.id}
              href={`/${item.slug}`}
              className="rounded-lg bg-card p-3 text-sm shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md"
            >
              <p className="line-clamp-2 font-bold">{item.title}</p>
              <div className="mt-2 flex items-center justify-between gap-2">
                <CategoryBadge category={item.category as FeatureCategory} />
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <span className="flex items-center gap-0.5">
                    <ChevronUp className="h-3 w-3" />
                    {item.upvote_count}
                  </span>
                  <span className="flex items-center gap-0.5">
                    <MessageSquare className="h-3 w-3" />
                    {item.comment_count}
                  </span>
                </div>
              </div>
            </Link>
          ))
        )}
      </div>
    </div>
  );
}

export function RequestsKanban({ byStatus }: { byStatus: Map<FeatureStatus, RoadmapItem[]> }) {
  return (
    <div className="flex flex-col gap-6 sm:flex-row">
      {BUCKETS.map((bucket) => (
        <SummaryColumn
          key={bucket.key}
          label={bucket.label}
          items={bucket.statuses.flatMap((status) => byStatus.get(status) ?? [])}
        />
      ))}
    </div>
  );
}
