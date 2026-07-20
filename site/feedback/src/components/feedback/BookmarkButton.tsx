"use client";

import { Bookmark } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useUser } from "@/lib/auth/useUser";
import { useMyBookmarkIds, useToggleBookmark } from "@/lib/queries/useBookmarks";

export function BookmarkButton({ featureId }: { featureId: string }) {
  const { user } = useUser();
  const { data: bookmarkIds } = useMyBookmarkIds(user?.id);
  const toggleBookmark = useToggleBookmark();

  if (!user) return null;

  const isBookmarked = bookmarkIds?.has(featureId) ?? false;

  return (
    <Button
      type="button"
      variant="ghost"
      size="icon"
      aria-pressed={isBookmarked}
      aria-label={isBookmarked ? "Remove bookmark" : "Bookmark this request"}
      disabled={toggleBookmark.isPending}
      onClick={(event) => {
        event.preventDefault();
        event.stopPropagation();
        toggleBookmark.mutate({ featureId, userId: user.id, isCurrentlyBookmarked: isBookmarked });
      }}
    >
      <Bookmark className={cn("h-4 w-4", isBookmarked && "fill-primary text-primary")} />
    </Button>
  );
}
