"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { RoadmapColumn } from "@/components/feedback/RoadmapColumn";
import { useRoadmap } from "@/lib/queries/useRoadmap";
import { ROADMAP_STATUSES } from "@/lib/utils/constants";

export default function RoadmapPage() {
  const { data, isLoading } = useRoadmap();

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <h1 className="text-2xl font-semibold tracking-tight">Roadmap</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        What we&apos;re building next, straight from your feedback.
      </p>

      <div className="mt-6 flex gap-4 overflow-x-auto pb-4">
        {isLoading
          ? ROADMAP_STATUSES.map((status) => (
              <div key={status} className="flex w-72 shrink-0 flex-col gap-2">
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-20 w-full rounded-lg" />
                <Skeleton className="h-20 w-full rounded-lg" />
              </div>
            ))
          : ROADMAP_STATUSES.map((status) => (
              <RoadmapColumn key={status} status={status} items={data?.get(status) ?? []} />
            ))}
      </div>
    </div>
  );
}
