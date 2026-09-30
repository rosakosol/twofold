"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useUser } from "@/lib/auth/useUser";
import { useMyVoteIds, useVote } from "@/lib/queries/useVote";

interface VoteButtonProps {
  featureId: string;
  upvoteCount: number;
}

export function VoteButton({ featureId, upvoteCount }: VoteButtonProps) {
  const { user, isLoading } = useUser();
  const pathname = usePathname();
  const { data: voteIds } = useMyVoteIds(user?.id);
  const vote = useVote();

  const hasVoted = voteIds?.has(featureId) ?? false;

  const arrow = (
    <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4}>
      <path d="M6 15l6-6 6 6" />
    </svg>
  );

  // Reading the board is public, so a signed-out visitor still sees every count — only casting a
  // vote needs an account. This was a `<button>` that pushed to /auth/sign-in from its onClick,
  // which worked but said nothing: the control looked like a vote and silently turned out to be a
  // login. A real link says where it goes (hover, status bar, screen reader, middle-click) and
  // carries the page back in `next`, so the vote is one press away from returning.
  //
  // `isLoading` is not this branch: the session is unknown for the first moment after mount, and
  // rendering the prompt then would flash "Sign in to vote" at everybody, signed in or not. The
  // button below handles that window — it is inert until a user arrives, which is the same thing
  // `vote.isPending` already does to it.
  if (!user && !isLoading) {
    return (
      <Link
        href={`/auth/sign-in?next=${encodeURIComponent(pathname)}`}
        className="vote"
        title="Sign in to vote"
        aria-label={`Sign in to vote. ${upvoteCount} ${upvoteCount === 1 ? "vote" : "votes"} so far.`}
      >
        {arrow}
        <span className="count">{upvoteCount}</span>
      </Link>
    );
  }

  function handleClick(event: React.MouseEvent) {
    // Kept from when FeatureCard wrapped each row in a <Link> to a detail page. That page is gone
    // (see FeatureCardData's note), so there is nothing to suppress today — but a card that links
    // somewhere again must not navigate on a vote, and this is a cheaper thing to keep than to
    // rediscover.
    event.preventDefault();
    event.stopPropagation();
    if (!user) return;
    vote.mutate({ featureId, userId: user.id, isCurrentlyVoted: hasVoted });
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={vote.isPending || !user}
      aria-pressed={hasVoted}
      className={cn("vote", hasVoted && "voted")}
    >
      {arrow}
      <span className="count">{upvoteCount}</span>
    </button>
  );
}
