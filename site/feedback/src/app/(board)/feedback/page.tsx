"use client";

import { Suspense, useMemo } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { TriangleAlert } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { FeatureSubmitDialog } from "@/components/feedback/FeatureSubmitDialog";
import { SearchBar } from "@/components/feedback/SearchBar";
import { EmptyState } from "@/components/feedback/EmptyState";
import { PopularThisWeek } from "@/components/feedback/PopularThisWeek";
import { RequestsList } from "@/components/feedback/RequestsList";
import { RoadmapColumn } from "@/components/feedback/RoadmapColumn";
import { useRoadmap, type RoadmapItem } from "@/lib/queries/useRoadmap";
import { CATEGORY_LABELS, CATEGORY_VALUES, type FeatureCategory, type FeatureStatus } from "@/lib/utils/constants";

const ALL = "__all__";

// Roadmap simplified to 4 quick-glance stages instead of the full 6-value status enum —
// "considering" folds into Requested (both mean "not committed to yet"), and "closed" is
// excluded entirely (not a forward-looking state). Fixed 4-column grid instead of the old
// horizontally-scrolling row, so it always fits the viewport width.
const ROADMAP_BUCKETS: { key: string; label: string; statuses: FeatureStatus[] }[] = [
  { key: "requested", label: "Requested", statuses: ["requested", "considering"] },
  { key: "planned", label: "Planned", statuses: ["planned"] },
  { key: "in_progress", label: "In Progress", statuses: ["in_progress"] },
  { key: "shipped", label: "Shipped", statuses: ["released"] },
];

export default function HomePage() {
  return (
    <Suspense>
      <Board />
    </Suspense>
  );
}

function Board() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const category = (searchParams.get("category") as FeatureCategory | null) ?? undefined;
  const search = searchParams.get("q") ?? "";

  const { data, isLoading, isError, refetch } = useRoadmap();

  const filtered = useMemo(() => {
    if (!data) return undefined;
    const q = search.trim().toLowerCase();
    const next = new Map<FeatureStatus, RoadmapItem[]>();
    for (const [status, items] of data) {
      next.set(
        status,
        items.filter(
          (item) => (!category || item.category === category) && (!q || item.title.toLowerCase().includes(q))
        )
      );
    }
    return next;
  }, [data, category, search]);

  function updateParam(key: string, value: string | undefined) {
    const params = new URLSearchParams(searchParams.toString());
    if (value) params.set(key, value);
    else params.delete(key);
    router.push(`/feedback?${params.toString()}`);
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="font-heading text-xl font-semibold tracking-tight">Feedback</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Vote on ideas, or tell us what would make Twofold better.
          </p>
        </div>
        <FeatureSubmitDialog />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[1fr_260px]">
        <div className="min-w-0">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="sm:max-w-xs sm:flex-1">
              <SearchBar value={search} onChange={(v) => updateParam("q", v || undefined)} />
            </div>
            <Select value={category ?? ALL} onValueChange={(v) => v && updateParam("category", v === ALL ? undefined : v)}>
              <SelectTrigger size="sm">
                <SelectValue placeholder="Category" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL}>All categories</SelectItem>
                {CATEGORY_VALUES.map((value) => (
                  <SelectItem key={value} value={value}>
                    {CATEGORY_LABELS[value]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="mt-6">
            {isError ? (
              <EmptyState
                icon={TriangleAlert}
                title="Couldn't load feedback"
                description="Something went wrong fetching requests — check your connection and try again."
                action={
                  <Button variant="outline" size="sm" onClick={() => refetch()}>
                    Retry
                  </Button>
                }
              />
            ) : isLoading || !filtered ? (
              <div className="flex flex-col gap-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Skeleton key={i} className="h-12 w-full rounded-lg" />
                ))}
              </div>
            ) : (
              <RequestsList byStatus={filtered} />
            )}
          </div>
        </div>

        <aside className="lg:pt-[52px]">
          <PopularThisWeek />
        </aside>
      </div>

      <div className="mt-10 border-t pt-6">
        <h2 className="font-heading text-lg font-semibold tracking-tight">Roadmap</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          The fuller picture, stage by stage.
        </p>
        <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
          {isError ? null : isLoading || !filtered
            ? ROADMAP_BUCKETS.map((bucket) => (
                <div key={bucket.key} className="flex min-w-0 flex-col gap-2">
                  <Skeleton className="h-4 w-24" />
                  <Skeleton className="h-20 w-full rounded-lg" />
                  <Skeleton className="h-20 w-full rounded-lg" />
                </div>
              ))
            : ROADMAP_BUCKETS.map((bucket) => (
                <RoadmapColumn
                  key={bucket.key}
                  label={bucket.label}
                  items={bucket.statuses.flatMap((status) => filtered.get(status) ?? [])}
                />
              ))}
        </div>
      </div>
    </div>
  );
}
