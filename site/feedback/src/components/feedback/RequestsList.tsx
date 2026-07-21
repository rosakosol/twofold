import { FeatureCard } from "@/components/feedback/FeatureCard";
import { EmptyState } from "@/components/feedback/EmptyState";
import type { FeatureStatus } from "@/lib/utils/constants";
import type { RoadmapItem } from "@/lib/queries/useRoadmap";

/** Flat, single-row-per-item list of every request — replaces the old 3-bucket kanban
 * summary, which just duplicated what the Roadmap section below already shows stage by
 * stage. Sorted by upvotes since there's no column grouping to sort within anymore. */
export function RequestsList({ byStatus }: { byStatus: Map<FeatureStatus, RoadmapItem[]> }) {
  const items = Array.from(byStatus.values())
    .flat()
    .sort((a, b) => b.upvote_count - a.upvote_count);

  if (items.length === 0) {
    return <EmptyState title="No requests yet" description="Be the first to suggest something." />;
  }

  return (
    <div className="flex flex-col gap-3">
      {items.map((item) => (
        <FeatureCard key={item.id} feature={item} />
      ))}
    </div>
  );
}
