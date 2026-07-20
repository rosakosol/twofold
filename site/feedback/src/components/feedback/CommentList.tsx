"use client";

import { Trash2 } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useUser } from "@/lib/auth/useUser";
import { useComments, useDeleteComment } from "@/lib/queries/useComments";
import { formatRelativeTime } from "@/lib/utils/format";

function avatarUrl(userId: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
}

export function CommentList({ featureId }: { featureId: string }) {
  const { user } = useUser();
  const { data: comments, isLoading } = useComments(featureId);
  const deleteComment = useDeleteComment(featureId);

  if (isLoading) {
    return (
      <div className="space-y-4">
        {Array.from({ length: 2 }).map((_, i) => (
          <Skeleton key={i} className="h-16 w-full rounded-lg" />
        ))}
      </div>
    );
  }

  if (!comments || comments.length === 0) {
    return <p className="text-sm text-muted-foreground">No comments yet — be the first.</p>;
  }

  return (
    <ul className="space-y-4">
      {comments.map((comment) => {
        const initials = (comment.author?.display_name ?? "?").slice(0, 2).toUpperCase();
        const canDelete = user?.id === comment.user_id;

        return (
          <li key={comment.id} className="flex gap-3">
            <Avatar className="h-7 w-7 shrink-0">
              <AvatarImage src={avatarUrl(comment.user_id)} alt="" />
              <AvatarFallback className="text-xs">{initials}</AvatarFallback>
            </Avatar>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">{comment.author?.display_name ?? "Twofold user"}</span>
                <span className="text-xs text-muted-foreground">{formatRelativeTime(comment.created_at)}</span>
              </div>
              <p className="mt-0.5 text-sm whitespace-pre-wrap">{comment.body}</p>
            </div>
            {canDelete && (
              <Button
                variant="ghost"
                size="icon-sm"
                className="shrink-0 text-muted-foreground hover:text-destructive"
                onClick={() => deleteComment.mutate(comment.id)}
                aria-label="Delete comment"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            )}
          </li>
        );
      })}
    </ul>
  );
}
