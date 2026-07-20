"use client";

import Link from "next/link";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { VoteButton } from "@/components/feedback/VoteButton";
import { VoterAvatarStack } from "@/components/feedback/VoterAvatarStack";
import { FeatureStatusBadge } from "@/components/feedback/FeatureStatusBadge";
import { CategoryBadge } from "@/components/feedback/CategoryBadge";
import { StatusTimeline } from "@/components/feedback/StatusTimeline";
import { SubscribeButton } from "@/components/feedback/SubscribeButton";
import { BookmarkButton } from "@/components/feedback/BookmarkButton";
import { DeveloperUpdateCard } from "@/components/feedback/DeveloperUpdateCard";
import { CommentList } from "@/components/feedback/CommentList";
import { CommentComposer } from "@/components/feedback/CommentComposer";
import { useFeature, useRelatedFeatures, type FeatureDetail } from "@/lib/queries/useFeature";
import { useDeveloperUpdates } from "@/lib/queries/useDeveloperUpdates";
import { formatDate } from "@/lib/utils/format";
import type { FeatureCategory, FeatureStatus } from "@/lib/utils/constants";

function avatarUrl(userId: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
}

export function FeatureDetailView({ initialFeature }: { initialFeature: FeatureDetail }) {
  const { data: feature } = useFeature(initialFeature.slug, initialFeature);
  const { data: updates } = useDeveloperUpdates(feature!.id);
  const { data: related } = useRelatedFeatures(feature?.category as FeatureCategory | undefined, feature?.id);

  if (!feature) return null; // initialData guarantees this never actually renders

  const initials = (feature.author?.display_name ?? "?").slice(0, 2).toUpperCase();

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <Link href="/" className="text-sm text-muted-foreground hover:text-foreground">
        ← Back to feedback
      </Link>

      <div className="mt-4 flex gap-4">
        <VoteButton featureId={feature.id} upvoteCount={feature.upvote_count} />

        <div className="min-w-0 flex-1">
          <h1 className="text-xl font-semibold tracking-tight">{feature.title}</h1>

          <div className="mt-2 flex flex-wrap items-center gap-2">
            <FeatureStatusBadge status={feature.status as FeatureStatus} />
            <CategoryBadge category={feature.category as FeatureCategory} />
            {feature.author && (
              <div className="ml-1 flex items-center gap-1.5">
                <Avatar className="h-5 w-5">
                  <AvatarImage src={avatarUrl(feature.author.id)} alt="" />
                  <AvatarFallback className="text-[10px]">{initials}</AvatarFallback>
                </Avatar>
                <span className="text-xs text-muted-foreground">
                  Requested by {feature.author.display_name} · {formatDate(feature.created_at)}
                </span>
              </div>
            )}
            {feature.upvote_count > 0 && (
              <VoterAvatarStack featureId={feature.id} totalVotes={feature.upvote_count} />
            )}
            <div className="ml-auto flex items-center gap-1">
              <BookmarkButton featureId={feature.id} />
              <SubscribeButton featureId={feature.id} />
            </div>
          </div>

          {feature.description && (
            <p className="mt-4 whitespace-pre-wrap text-sm text-foreground/90">{feature.description}</p>
          )}
        </div>
      </div>

      <div className="mt-6">
        <StatusTimeline status={feature.status as FeatureStatus} />
      </div>

      {updates && updates.length > 0 && (
        <div className="mt-8 space-y-3">
          {updates.map((update) => (
            <DeveloperUpdateCard key={update.id} update={update} />
          ))}
        </div>
      )}

      <Separator className="my-8" />

      <div>
        <h2 className="text-sm font-semibold">Comments ({feature.comment_count})</h2>
        <div className="mt-4">
          <CommentComposer featureId={feature.id} />
        </div>
        <div className="mt-6">
          <CommentList featureId={feature.id} />
        </div>
      </div>

      {related && related.length > 0 && (
        <>
          <Separator className="my-8" />
          <div>
            <h2 className="text-sm font-semibold">Related requests</h2>
            <ul className="mt-3 space-y-2">
              {related.map((item) => (
                <li key={item.id}>
                  <Link
                    href={`/${item.slug}`}
                    className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm hover:border-primary/40 hover:bg-accent/40"
                  >
                    <span className="truncate">{item.title}</span>
                    <span className="ml-2 shrink-0 text-xs text-muted-foreground">
                      {item.upvote_count} votes
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </>
      )}
    </div>
  );
}

export function FeatureDetailSkeleton() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-10 space-y-4">
      <Skeleton className="h-4 w-24" />
      <Skeleton className="h-8 w-3/4" />
      <Skeleton className="h-20 w-full" />
    </div>
  );
}
