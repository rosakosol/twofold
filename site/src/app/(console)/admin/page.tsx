"use client";

import { useState } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { SearchBar } from "@/components/feedback/SearchBar";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { AdminFeatureTable } from "@/components/admin/AdminFeatureTable";
import { ConsoleEmpty, ConsolePageHead, StatTiles } from "@/components/console/ConsoleUI";
import { useAdminFeatureList, type AdminFeatureFilters } from "@/lib/queries/useAdminFeatures";
import { STATUS_LABELS, STATUS_VALUES, type FeatureStatus } from "@/lib/utils/constants";

const ALL = "__all__";

/** The public board, from the inside (docs/TWOFOLD_WEBSITE.md, section 9.2): set a status, merge,
 *  pin, and post updates. */
export default function AdminPage() {
  const [status, setStatus] = useState<FeatureStatus | undefined>(undefined);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<AdminFeatureFilters["sort"]>("newest");

  const { data: features, isLoading } = useAdminFeatureList({ status, search: search || undefined, sort });
  // Every request, whatever the filters, for the tiles: they describe the board, not the view of it.
  const { data: everything } = useAdminFeatureList({ sort: "newest" });

  const all = everything ?? [];
  const live = all.filter((f) => !f.merged_into);
  const isEmptyBoard = everything !== undefined && all.length === 0;

  return (
    <div>
      <ConsolePageHead
        title="Feedback requests"
        description="Requests from the public feedback board. Set a status, merge duplicates, pin and post updates."
      />

      <StatTiles
        items={[
          { label: "Requests", value: everything ? live.length : "–" },
          { label: "Total votes", value: everything ? live.reduce((sum, f) => sum + f.upvote_count, 0) : "–" },
          {
            label: "Waiting for a status",
            value: everything ? live.filter((f) => f.status === "requested").length : "–",
            hint: "Still marked Requested",
          },
          { label: "Shipped", value: everything ? live.filter((f) => f.status === "released").length : "–" },
        ]}
      />

      {isEmptyBoard ? (
        <ConsoleEmpty title="No requests yet">
          When someone posts on the public board at /feedback, it appears here to triage: give it a status, merge it
          into a duplicate, or pin it.
        </ConsoleEmpty>
      ) : (
        <>
          <div className="console-filters">
            <div className="console-search">
              <SearchBar value={search} onChange={setSearch} placeholder="Search requests" />
            </div>

            <Select value={status ?? ALL} onValueChange={(v) => setStatus(!v || v === ALL ? undefined : (v as FeatureStatus))}>
              <SelectTrigger aria-label="Status">
                <SelectValue placeholder="Status" labels={{ [ALL]: "All statuses", ...STATUS_LABELS }} />
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
              <SelectTrigger aria-label="Sort">
                <SelectValue labels={{ newest: "Newest", popularity: "Most popular" }} />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="newest">Newest</SelectItem>
                <SelectItem value="popularity">Most popular</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {isLoading ? <Skeleton className="h-64 w-full rounded-2xl" /> : <AdminFeatureTable features={features ?? []} />}
        </>
      )}
    </div>
  );
}
