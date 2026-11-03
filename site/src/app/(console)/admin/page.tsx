"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Skeleton } from "@/components/ui/skeleton";
import { SearchBar } from "@/components/feedback/SearchBar";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { AdminFeatureTable } from "@/components/admin/AdminFeatureTable";
import { ConsoleEmpty, ConsolePageHead, StatTiles, ConsoleError } from "@/components/console/ConsoleUI";
import { useAdminFeatureList, type AdminFeatureFilters } from "@/lib/queries/useAdminFeatures";
import { useAdminRolesState } from "@/lib/auth/useAdminRoles";
import { STATUS_LABELS, STATUS_VALUES, type FeatureStatus } from "@/lib/utils/constants";

const ALL = "__all__";

/** The public board, from the inside (docs/TWOFOLD_WEBSITE.md, section 9.2): set a status, merge,
 *  pin and edit. */
export default function AdminPage() {
  const { roles, isLoaded } = useAdminRolesState();
  const [status, setStatus] = useState<FeatureStatus | undefined>(undefined);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<AdminFeatureFilters["sort"]>("newest");

  const { data: features, isLoading, isError, refetch } = useAdminFeatureList({ status, search: search || undefined, sort });
  // Every request, whatever the filters, for the tiles: they describe the board, not the view of it.
  const { data: everything } = useAdminFeatureList({ sort: "newest" });

  const all = everything ?? [];
  const live = all.filter((f) => !f.merged_into);
  const isEmptyBoard = everything !== undefined && all.length === 0;

  return (
    <div>
      <ConsolePageHead
        title="Feedback requests"
        description="Requests from the public feedback board. Set a status, merge duplicates, pin and edit."
      />

      <Suspense>
        <DeniedNotice />
      </Suspense>
      {isLoaded && !roles.content && (
        <p className="field-hint">
          You can read the board here, but changing requests needs the content role.
        </p>
      )}

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

          {isLoading ? (
            <Skeleton className="h-64 w-full rounded-2xl" />
          ) : isError ? (
            // Not the table's "No requests match these filters", which is what a failed read used to say.
            <ConsoleError title="Requests didn't load" onRetry={() => void refetch()} />
          ) : (
            <AdminFeatureTable features={features ?? []} />
          )}
        </>
      )}
    </div>
  );
}

const ROLE_NAMES: Record<string, string> = { support: "support", billing: "billing" };

/**
 * Why somebody has just landed here. A page whose role you don't hold sends you to /admin, which
 * used to happen silently, so following a colleague's link to /admin/usage just showed Feedback.
 */
function DeniedNotice() {
  const role = ROLE_NAMES[useSearchParams().get("denied") ?? ""];
  if (!role) return null;
  return (
    <p className="field-error" role="status">
      That page needs the {role} role, which this account doesn&apos;t have. Ask whoever manages console
      access if you need it.
    </p>
  );
}
