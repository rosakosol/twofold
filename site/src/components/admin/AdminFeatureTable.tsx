"use client";

import Link from "next/link";
import { Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CategoryBadge } from "@/components/feedback/CategoryBadge";
import { StatusSelect } from "@/components/admin/StatusSelect";
import { PinToggle } from "@/components/admin/PinToggle";
import { MergeDialog } from "@/components/admin/MergeDialog";
import { DeleteConfirmDialog } from "@/components/admin/DeleteConfirmDialog";
import { ConsoleEmpty } from "@/components/console/ConsoleUI";
import type { FeatureDetail } from "@/lib/queries/useFeature";
import type { FeatureCategory, FeatureStatus } from "@/lib/utils/constants";

export function AdminFeatureTable({ features }: { features: FeatureDetail[] }) {
  if (features.length === 0) {
    return <ConsoleEmpty title="No requests match these filters" />;
  }

  return (
    <div className="console-table-wrap">
      <table className="console-table">
        <thead>
          <tr>
            <th scope="col">Title</th>
            <th scope="col">Category</th>
            <th scope="col">Status</th>
            <th scope="col">Votes</th>
            <th scope="col">Comments</th>
            <th scope="col">Pinned</th>
            <th scope="col">
              <span className="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {features.map((feature) => (
            <tr key={feature.id} className={feature.merged_into ? "opacity-50" : undefined}>
              <td className="max-w-72 truncate">
                {feature.title}
                {feature.merged_into && <span className="muted"> (merged)</span>}
              </td>
              <td>
                <CategoryBadge category={feature.category as FeatureCategory} />
              </td>
              <td>
                <StatusSelect featureId={feature.id} status={feature.status as FeatureStatus} />
              </td>
              <td className="num">{feature.upvote_count}</td>
              <td className="num">{feature.comment_count}</td>
              <td>
                <PinToggle featureId={feature.id} isPinned={feature.is_pinned} />
              </td>
              <td>
                <div className="flex items-center justify-end gap-1">
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="text-muted-foreground"
                    render={<Link href={`/admin/requests/${feature.id}`} aria-label={`Edit ${feature.title}`} />}
                  >
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <MergeDialog featureId={feature.id} title={feature.title} />
                  <DeleteConfirmDialog featureId={feature.id} title={feature.title} />
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
