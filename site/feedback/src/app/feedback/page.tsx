"use client";

import { Suspense, useEffect, useMemo, useRef } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2, TriangleAlert } from "lucide-react";
import { FeatureCard } from "@/components/feedback/FeatureCard";
import { FeatureSubmitDialog } from "@/components/feedback/FeatureSubmitDialog";
import { SearchBar } from "@/components/feedback/SearchBar";
import { Filters } from "@/components/feedback/Filters";
import { EmptyState } from "@/components/feedback/EmptyState";
import { PopularThisWeek } from "@/components/feedback/PopularThisWeek";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { useInfiniteFeatureList } from "@/lib/queries/useFeatureList";
import type { FeatureCategory, FeatureStatus, SortOption } from "@/lib/utils/constants";

export default function FeedbackPage() {
  return (
    <Suspense>
      <FeedbackBoard />
    </Suspense>
  );
}

function FeedbackBoard() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const category = (searchParams.get("category") as FeatureCategory | null) ?? undefined;
  const status = (searchParams.get("status") as FeatureStatus | null) ?? undefined;
  const sort = (searchParams.get("sort") as SortOption | null) ?? "top";
  const search = searchParams.get("q") ?? "";

  const filters = useMemo(() => ({ category, status, sort, search: search || undefined }), [category, status, sort, search]);
  const { data, isLoading, isError, refetch, isFetchingNextPage, hasNextPage, fetchNextPage } =
    useInfiniteFeatureList(filters);

  const items = useMemo(() => data?.pages.flatMap((p) => p.items) ?? [], [data]);

  const sentinelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) {
          fetchNextPage();
        }
      },
      { rootMargin: "400px" }
    );

    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  function updateParam(key: string, value: string | undefined) {
    const params = new URLSearchParams(searchParams.toString());
    if (value) params.set(key, value);
    else params.delete(key);
    router.push(`/feedback?${params.toString()}`);
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-10">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Feedback</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Vote on ideas, or tell us what would make Twofold better.
          </p>
        </div>
        <FeatureSubmitDialog />
      </div>

      <div className="mt-8 grid grid-cols-1 gap-8 lg:grid-cols-[1fr_260px]">
        <div className="min-w-0">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="sm:max-w-xs sm:flex-1">
              <SearchBar value={search} onChange={(v) => updateParam("q", v || undefined)} />
            </div>
            <Filters
              category={category}
              status={status}
              sort={sort}
              onCategoryChange={(v) => updateParam("category", v)}
              onStatusChange={(v) => updateParam("status", v)}
              onSortChange={(v) => updateParam("sort", v)}
            />
          </div>

          <div className="mt-6 flex flex-col gap-3">
            {isLoading ? (
              Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-24 w-full rounded-xl" />)
            ) : isError ? (
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
            ) : items.length === 0 ? (
              <EmptyState
                title="No feedback yet"
                description="Be the first to request a feature."
              />
            ) : (
              items.map((feature) => <FeatureCard key={feature.id} feature={feature} />)
            )}
          </div>

          {!isError && items.length > 0 && (
            <div ref={sentinelRef} className="mt-6 flex items-center justify-center py-4">
              {isFetchingNextPage && <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />}
            </div>
          )}
        </div>

        <aside className="lg:pt-[52px]">
          <PopularThisWeek />
        </aside>
      </div>
    </div>
  );
}
