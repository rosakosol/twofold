import Link from "next/link";
import { ChevronUp, MessageSquare } from "lucide-react";
import { CategoryBadge } from "@/components/feedback/CategoryBadge";
import { STATUS_LABELS, type FeatureCategory, type FeatureStatus } from "@/lib/utils/constants";
import type { RoadmapItem } from "@/lib/queries/useRoadmap";

export function RoadmapColumn({ status, items }: { status: FeatureStatus; items: RoadmapItem[] }) {
  return (
    <div className="flex w-72 shrink-0 flex-col gap-3">
      <div className="flex items-center gap-2 px-1">
        <h2 className="text-sm font-semibold">{STATUS_LABELS[status]}</h2>
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
              href={`/feedback/${item.slug}`}
              className="rounded-lg border bg-card p-3 text-sm transition-colors hover:border-primary/40 hover:bg-accent/40"
            >
              <p className="line-clamp-2 font-medium">{item.title}</p>
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
