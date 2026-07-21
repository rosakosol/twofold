"use client";

import Link from "next/link";
import { Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CategoryBadge } from "@/components/feedback/CategoryBadge";
import { StatusSelect } from "@/components/admin/StatusSelect";
import { PinToggle } from "@/components/admin/PinToggle";
import { MergeDialog } from "@/components/admin/MergeDialog";
import { DeleteConfirmDialog } from "@/components/admin/DeleteConfirmDialog";
import type { FeatureDetail } from "@/lib/queries/useFeature";
import type { FeatureCategory, FeatureStatus } from "@/lib/utils/constants";

export function AdminFeatureTable({ features }: { features: FeatureDetail[] }) {
  if (features.length === 0) {
    return <p className="py-12 text-center text-sm text-muted-foreground">No requests match these filters.</p>;
  }

  return (
    <div className="overflow-x-auto rounded-lg border">
      <table className="w-full text-sm">
        <thead className="border-b bg-muted/50 text-left text-xs text-muted-foreground">
          <tr>
            <th className="px-3 py-2 font-medium">Title</th>
            <th className="px-3 py-2 font-medium">Category</th>
            <th className="px-3 py-2 font-medium">Status</th>
            <th className="px-3 py-2 font-medium">Votes</th>
            <th className="px-3 py-2 font-medium">Comments</th>
            <th className="px-3 py-2 font-medium">Pinned</th>
            <th className="px-3 py-2 font-medium">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y">
          {features.map((feature) => (
            <tr key={feature.id} className={feature.merged_into ? "opacity-50" : undefined}>
              <td className="max-w-64 truncate px-3 py-2">
                <Link href={`/feedback/${feature.slug}`} className="hover:text-primary hover:underline">
                  {feature.title}
                </Link>
                {feature.merged_into && (
                  <span className="ml-1 text-xs text-muted-foreground">(merged)</span>
                )}
              </td>
              <td className="px-3 py-2">
                <CategoryBadge category={feature.category as FeatureCategory} />
              </td>
              <td className="px-3 py-2">
                <StatusSelect featureId={feature.id} status={feature.status as FeatureStatus} />
              </td>
              <td className="px-3 py-2 tabular-nums">{feature.upvote_count}</td>
              <td className="px-3 py-2 tabular-nums">{feature.comment_count}</td>
              <td className="px-3 py-2">
                <PinToggle featureId={feature.id} isPinned={feature.is_pinned} />
              </td>
              <td className="px-3 py-2">
                <div className="flex items-center gap-1">
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="text-muted-foreground"
                    render={<Link href={`/admin/requests/${feature.id}`} aria-label="Edit" />}
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
