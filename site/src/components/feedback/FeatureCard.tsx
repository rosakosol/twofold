import { MessageCircle, Pin } from "lucide-react";
import { VoteButton } from "@/components/feedback/VoteButton";
import { FeatureStatusPill } from "@/components/feedback/FeatureStatusPill";
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

/** A request on the board (docs/TWOFOLD_WEBSITE.md, section 8): the vote on the left, then the
 *  title, description, status, category, who asked and when, and the comment count. */
export function FeatureCard({ feature }: { feature: FeatureCardData }) {
  const status = feature.status as FeatureStatus;
  const comments = feature.comment_count;

  return (
    <article className="fb-item" aria-labelledby={`req-${feature.id}`}>
      <VoteButton featureId={feature.id} upvoteCount={feature.upvote_count} title={feature.title} />

      <div className="fb-body">
        <h3 id={`req-${feature.id}`} className="fb-title">
          {feature.is_pinned && <Pin className="fb-pin" aria-label="Pinned" role="img" />}
          {feature.title}
        </h3>
        {feature.description && <p className="fb-desc">{feature.description}</p>}
        <div className="fb-foot">
          <FeatureStatusPill status={status} />
          <span className="pill pill-raised">{CATEGORY_LABELS[feature.category as FeatureCategory]}</span>
          <span className="fb-meta">
            {feature.author?.display_name ?? "Anonymous"}, {formatRelativeTime(feature.created_at)}
          </span>
          <span className="fb-comments" aria-label={`${comments} ${comments === 1 ? "comment" : "comments"}`}>
            <MessageCircle aria-hidden />
            {comments}
          </span>
        </div>
      </div>
    </article>
  );
}
