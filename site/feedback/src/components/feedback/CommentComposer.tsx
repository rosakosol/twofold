"use client";

import { useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import { Loader2, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { useUser } from "@/lib/auth/useUser";
import { useCreateComment } from "@/lib/queries/useComments";
import { createCommentSchema } from "@/lib/validation/comment";

export function CommentComposer({ featureId }: { featureId: string }) {
  const { user } = useUser();
  const router = useRouter();
  const pathname = usePathname();
  const createComment = useCreateComment(featureId);

  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);

  if (!user) {
    return (
      <Button
        variant="outline"
        className="w-full"
        onClick={() => router.push(`/auth/sign-in?next=${encodeURIComponent(pathname)}`)}
      >
        Sign in to comment
      </Button>
    );
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const result = createCommentSchema.safeParse({ body });
    if (!result.success) {
      setError(result.error.issues[0]?.message ?? "Invalid comment.");
      return;
    }
    setError(null);

    try {
      await createComment.mutateAsync({ body: result.data.body, userId: user!.id });
      setBody("");
    } catch {
      setError("Something went wrong — try again.");
    }
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLTextAreaElement>) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-2">
      {/* Textarea already auto-expands (field-sizing: content, see ui/textarea.tsx) */}
      <Textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        onKeyDown={handleKeyDown}
        placeholder="Add a comment…"
        rows={3}
        className="max-h-64 overflow-y-auto"
      />
      {error && <p className="text-sm text-destructive">{error}</p>}
      <div className="flex justify-end">
        <Button type="submit" size="sm" disabled={createComment.isPending || !body.trim()}>
          {createComment.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          Comment
        </Button>
      </div>
    </form>
  );
}
