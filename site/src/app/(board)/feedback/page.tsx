"use client";

import "./feedback.css";
import { Suspense, useMemo } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { MessagesSquare, TriangleAlert } from "lucide-react";
import { StatusPill } from "@/components/site/StatusPill";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { FeatureSubmitDialog } from "@/components/feedback/FeatureSubmitDialog";
import { SearchBar } from "@/components/feedback/SearchBar";
import { EmptyState } from "@/components/feedback/EmptyState";
import { RequestsList } from "@/components/feedback/RequestsList";
import { RoadmapColumn } from "@/components/feedback/RoadmapColumn";
import { useRoadmap, type RoadmapItem } from "@/lib/queries/useRoadmap";
import { CATEGORY_LABELS, CATEGORY_VALUES, type FeatureCategory, type FeatureStatus } from "@/lib/utils/constants";

const ALL = "__all__";

// Roadmap simplified to 4 quick-glance stages instead of the full 6-value status enum -
// "considering" folds into Requested (both mean "not committed to yet"), and "closed" is
// excluded entirely (not a forward-looking state). Matches design_handoff_twofold_site/
// feedback.html's 4-column board exactly.
const ROADMAP_BUCKETS: { key: string; label: string; statuses: FeatureStatus[] }[] = [
  { key: "requested", label: "Requested", statuses: ["requested", "considering"] },
  { key: "planned", label: "Planned", statuses: ["planned"] },
  { key: "in_progress", label: "In progress", statuses: ["in_progress"] },
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
    <div className="fb-page">
      <header className="fb-head">
        <StatusPill tone="surface" icon={<MessagesSquare />}>
          Feedback
        </StatusPill>
        <h1>Help shape what Twofold becomes</h1>
        <p className="lead">Vote on ideas, or tell us what would make Twofold better.</p>
        <FeatureSubmitDialog />
      </header>

      <div className="fb-controls">
        <SearchBar value={search} onChange={(v) => updateParam("q", v || undefined)} />
        <div className="fb-category">
          <span id="fb-category-label" className="field-label">
            Category
          </span>
          <Select value={category ?? ALL} onValueChange={(v) => v && updateParam("category", v === ALL ? undefined : v)}>
            <SelectTrigger className="fb-select" aria-labelledby="fb-category-label">
              <SelectValue placeholder="Category" labels={{ [ALL]: "All categories", ...CATEGORY_LABELS }} />
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
      </div>

      <h2 className="sr-only">Requests</h2>

      {isError ? (
        <EmptyState
          icon={TriangleAlert}
          title="Couldn't load feedback"
          description="Something went wrong fetching requests - check your connection and try again."
          action={
            <Button variant="outline" size="sm" onClick={() => refetch()}>
              Retry
            </Button>
          }
        />
      ) : isLoading || !filtered ? (
        <div className="fb-list">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-24 w-full rounded-2xl" />
          ))}
        </div>
      ) : (
        <RequestsList byStatus={filtered} />
      )}

      <div className="roadmap-head">
        <h2>Roadmap</h2>
        <p>The fuller picture, stage by stage.</p>
      </div>
      {/* Four columns on a desktop; on a phone they scroll sideways, so the region takes focus. */}
      <div className="roadmap" tabIndex={0} role="group" aria-label="Roadmap stages">
        {isError ? null : isLoading || !filtered
          ? ROADMAP_BUCKETS.map((bucket) => (
              <div key={bucket.key} className="flex min-w-0 flex-col gap-2">
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-20 w-full rounded-2xl" />
                <Skeleton className="h-20 w-full rounded-2xl" />
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
  );
}
