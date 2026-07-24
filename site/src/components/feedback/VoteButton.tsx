"use client";

import { useRouter, usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useUser } from "@/lib/auth/useUser";
import { useMyVoteIds, useVote } from "@/lib/queries/useVote";

interface VoteButtonProps {
  featureId: string;
  upvoteCount: number;
}

export function VoteButton({ featureId, upvoteCount }: VoteButtonProps) {
  const { user } = useUser();
  const pathname = usePathname();
  const router = useRouter();
  const { data: voteIds } = useMyVoteIds(user?.id);
  const vote = useVote();

  const hasVoted = voteIds?.has(featureId) ?? false;

  function handleClick(event: React.MouseEvent) {
    event.preventDefault(); // these live inside <Link> feature cards
    event.stopPropagation();

    if (!user) {
      router.push(`/auth/sign-in?next=${encodeURIComponent(pathname)}`);
      return;
    }

    vote.mutate({ featureId, userId: user.id, isCurrentlyVoted: hasVoted });
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={vote.isPending}
      aria-pressed={hasVoted}
      className={cn("vote", hasVoted && "voted")}
    >
      <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4}>
        <path d="M6 15l6-6 6 6" />
      </svg>
      <span className="count">{upvoteCount}</span>
    </button>
  );
}
