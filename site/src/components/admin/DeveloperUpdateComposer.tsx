"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Loader2, Megaphone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { useUser } from "@/lib/auth/useUser";
import { usePostDeveloperUpdate } from "@/lib/queries/useAdminMutations";
import { developerUpdateSchema } from "@/lib/validation/admin";

export function DeveloperUpdateComposer({ featureId }: { featureId: string }) {
  const { user } = useUser();
  const postUpdate = usePostDeveloperUpdate(featureId);
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!user) return;

    const result = developerUpdateSchema.safeParse({ body });
    if (!result.success) {
      setError(result.error.issues[0]?.message ?? "Invalid update.");
      return;
    }
    setError(null);

    try {
      await postUpdate.mutateAsync({ body: result.data.body, authorId: user.id });
      setBody("");
      toast.success("Update posted");
    } catch {
      toast.error("Couldn't post that update.");
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-2">
      <Textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        placeholder="Post an update visible to everyone following this request…"
        rows={3}
      />
      {error && <p className="text-sm text-destructive">{error}</p>}
      <Button type="submit" size="sm" disabled={postUpdate.isPending || !body.trim()}>
        {postUpdate.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Megaphone className="h-4 w-4" />}
        Post update
      </Button>
    </form>
  );
}
