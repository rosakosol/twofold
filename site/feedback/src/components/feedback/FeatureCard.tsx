import Link from "next/link";
import { MessageSquare, Pin } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { VoteButton } from "@/components/feedback/VoteButton";
import { FeatureStatusBadge } from "@/components/feedback/FeatureStatusBadge";
import { CategoryBadge } from "@/components/feedback/CategoryBadge";
import { formatRelativeTime } from "@/lib/utils/format";
import type { FeatureListItem } from "@/lib/queries/useFeatureList";
import type { FeatureCategory, FeatureStatus } from "@/lib/utils/constants";

function avatarUrl(userId: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
}

export function FeatureCard({ feature }: { feature: FeatureListItem }) {
  const initials = (feature.author?.display_name ?? "?").slice(0, 2).toUpperCase();

  return (
    <Link
      href={`/feedback/${feature.slug}`}
      className="group flex gap-4 rounded-xl bg-card p-4 shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md"
    >
      <VoteButton featureId={feature.id} upvoteCount={feature.upvote_count} />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          {feature.is_pinned && <Pin className="h-3.5 w-3.5 shrink-0 text-primary" />}
          <h3 className="truncate font-bold group-hover:text-primary">{feature.title}</h3>
        </div>

        {feature.description && (
          <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{feature.description}</p>
        )}

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <FeatureStatusBadge status={feature.status as FeatureStatus} />
          <CategoryBadge category={feature.category as FeatureCategory} />

          <span className="flex items-center gap-1 text-xs text-muted-foreground">
            <MessageSquare className="h-3.5 w-3.5" />
            {feature.comment_count}
          </span>

          <span className="text-xs text-muted-foreground">
            {formatRelativeTime(feature.created_at)}
          </span>

          {feature.author && (
            <div className="ml-auto flex items-center gap-1.5">
              <Avatar className="h-5 w-5">
                <AvatarImage src={avatarUrl(feature.author.id)} alt="" />
                <AvatarFallback className="text-[10px]">{initials}</AvatarFallback>
              </Avatar>
              <span className="text-xs text-muted-foreground">{feature.author.display_name}</span>
            </div>
          )}
        </div>
      </div>
    </Link>
  );
}
