"use client";

import { useRouter, usePathname } from "next/navigation";
import { ChevronUp } from "lucide-react";
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
      className={cn(
        "flex flex-col items-center justify-center gap-0.5 rounded-lg border px-3 py-1.5 min-w-14 transition-all active:scale-90 disabled:pointer-events-none",
        hasVoted
          ? "border-primary bg-primary/10 text-primary"
          : "border-border bg-background text-muted-foreground hover:border-primary/50 hover:text-foreground"
      )}
    >
      <ChevronUp className={cn("h-4 w-4 transition-transform", hasVoted && "scale-110")} />
      <span className="text-sm font-semibold tabular-nums">{upvoteCount}</span>
    </button>
  );
}
