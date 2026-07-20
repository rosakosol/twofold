"use client";

import { useState } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { SearchBar } from "@/components/feedback/SearchBar";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { AdminFeatureTable } from "@/components/admin/AdminFeatureTable";
import { useAdminFeatureList, type AdminFeatureFilters } from "@/lib/queries/useAdminFeatures";
import { STATUS_LABELS, STATUS_VALUES, type FeatureStatus } from "@/lib/utils/constants";

const ALL = "__all__";

export default function AdminPage() {
  const [status, setStatus] = useState<FeatureStatus | undefined>(undefined);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<AdminFeatureFilters["sort"]>("newest");

  const { data: features, isLoading } = useAdminFeatureList({ status, search: search || undefined, sort });

  const totalVotes = (features ?? []).reduce((sum, f) => sum + f.upvote_count, 0);

  return (
    <div>
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-heading text-3xl font-bold tracking-tight">Admin</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {features?.length ?? 0} requests · {totalVotes} total votes
          </p>
        </div>
      </div>

      <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="sm:max-w-xs sm:flex-1">
          <SearchBar value={search} onChange={setSearch} placeholder="Search all requests…" />
        </div>

        <Select
          value={status ?? ALL}
          onValueChange={(v) => setStatus(!v || v === ALL ? undefined : (v as FeatureStatus))}
        >
          <SelectTrigger size="sm">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All statuses</SelectItem>
            {STATUS_VALUES.map((value) => (
              <SelectItem key={value} value={value}>
                {STATUS_LABELS[value]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select value={sort} onValueChange={(v) => setSort(v as AdminFeatureFilters["sort"])}>
          <SelectTrigger size="sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="newest">Newest</SelectItem>
            <SelectItem value="popularity">Most popular</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="mt-6">
        {isLoading ? (
          <Skeleton className="h-64 w-full rounded-lg" />
        ) : (
          <AdminFeatureTable features={features ?? []} />
        )}
      </div>
    </div>
  );
}
