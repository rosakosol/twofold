import { VoteButton } from "@/components/feedback/VoteButton";
import { CATEGORY_LABELS, STATUS_LABELS, type FeatureCategory, type FeatureStatus } from "@/lib/utils/constants";
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

// design_handoff_twofold_site/feedback.html only has 4 status-pill looks
// (Requested/Planned/In Progress/Shipped) — folds the real 6-value enum down the
// same way the roadmap buckets already do (considering -> requested, closed has no
// reference equivalent so it also reads as the neutral "requested" grey).
const STATUS_PILL_CLASS: Record<FeatureStatus, string> = {
  requested: "status-requested",
  considering: "status-requested",
  planned: "status-planned",
  in_progress: "status-progress",
  released: "status-shipped",
  closed: "status-requested",
};

export function FeatureCard({ feature }: { feature: FeatureCardData }) {
  const status = feature.status as FeatureStatus;

  return (
    <div className="fb-item">
      <VoteButton featureId={feature.id} upvoteCount={feature.upvote_count} />

      <div className="fb-body">
        <div className="fb-body-top">
          <div>
            <p className="fb-title">
              {feature.is_pinned && <span aria-hidden>📌 </span>}
              {feature.title}
            </p>
            {feature.description && <p className="fb-desc">{feature.description}</p>}
            <span className="fb-meta">
              {feature.author?.display_name ?? "Anonymous"} · {formatRelativeTime(feature.created_at)}
            </span>
          </div>
          <span className={`status ${STATUS_PILL_CLASS[status]}`}>{STATUS_LABELS[status]}</span>
        </div>
        <div className="fb-foot">
          <span className="tag">#{CATEGORY_LABELS[feature.category as FeatureCategory]}</span>
          <span className="fb-comments">
            <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
              <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z" />
            </svg>
            {feature.comment_count}
          </span>
        </div>
      </div>
    </div>
  );
}
