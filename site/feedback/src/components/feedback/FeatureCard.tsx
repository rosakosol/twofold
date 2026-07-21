import { MessageSquare, Pin } from "lucide-react";
import { VoteButton } from "@/components/feedback/VoteButton";
import { FeatureStatusBadge } from "@/components/feedback/FeatureStatusBadge";
import { CATEGORY_LABELS, type FeatureCategory, type FeatureStatus } from "@/lib/utils/constants";
import { formatRelativeTime } from "@/lib/utils/format";

/** Minimal shape any request-like row needs — deliberately smaller than the full
 * FeatureListItem/RoadmapItem types so both can be passed here structurally without
 * carrying fields this card doesn't use (slug, merged_into, etc. — there's no detail
 * page to link to anymore, so those never mattered here). */
export interface FeatureCardData {
  id: string;
  title: string;
  description: string | null;
  category: string;
  status: string;
  upvote_count: number;
  comment_count: number;
  created_at: string;
  is_pinned?: boolean;
  author: { display_name: string } | null;
}

export function FeatureCard({ feature }: { feature: FeatureCardData }) {
  return (
    <div className="flex gap-4 rounded-xl border bg-card p-4">
      <VoteButton featureId={feature.id} upvoteCount={feature.upvote_count} />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          {feature.is_pinned && <Pin className="h-3.5 w-3.5 shrink-0 text-primary" />}
          <h3 className="truncate font-semibold">{feature.title}</h3>
        </div>

        {feature.description && (
          <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{feature.description}</p>
        )}

        <div className="mt-2 flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
          <span>{feature.author?.display_name ?? "Anonymous"}</span>
          <span aria-hidden>·</span>
          <span>{formatRelativeTime(feature.created_at)}</span>
        </div>

        <span className="mt-2 inline-flex w-fit items-center rounded-md bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
          #{CATEGORY_LABELS[feature.category as FeatureCategory]}
        </span>
      </div>

      <div className="flex shrink-0 flex-col items-end justify-between gap-2">
        <FeatureStatusBadge status={feature.status as FeatureStatus} />
        <span className="flex items-center gap-1 text-xs text-muted-foreground">
          <MessageSquare className="h-3.5 w-3.5" />
          {feature.comment_count}
        </span>
      </div>
    </div>
  );
}
