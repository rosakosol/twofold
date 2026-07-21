"use client";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Skeleton } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/feedback/EmptyState";
import { FeatureStatusBadge } from "@/components/feedback/FeatureStatusBadge";
import { useChangelog } from "@/lib/queries/useChangelog";
import { formatDate } from "@/lib/utils/format";
import type { FeatureStatus } from "@/lib/utils/constants";
import { Megaphone } from "lucide-react";

function avatarUrl(userId: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
}

export default function ChangelogPage() {
  const { data: entries, isLoading } = useChangelog();

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <h1 className="font-heading text-xl font-semibold tracking-tight">Changelog</h1>
      <p className="mt-1 text-sm text-muted-foreground">Updates from the team, newest first.</p>

      <div className="mt-8 space-y-6">
        {isLoading ? (
          Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-28 w-full rounded-lg" />)
        ) : !entries || entries.length === 0 ? (
          <EmptyState icon={Megaphone} title="No updates yet" description="Check back soon." />
        ) : (
          entries.map((entry) => {
            const initials = (entry.author?.display_name ?? "?").slice(0, 2).toUpperCase();
            return (
              <div key={entry.id} className="border-b pb-6 last:border-b-0">
                <div className="flex items-center gap-2">
                  <Avatar className="h-6 w-6">
                    {entry.author && <AvatarImage src={avatarUrl(entry.author.id)} alt="" />}
                    <AvatarFallback className="text-[10px]">{initials}</AvatarFallback>
                  </Avatar>
                  <span className="text-sm font-medium">{entry.author?.display_name ?? "Twofold team"}</span>
                  <span className="text-xs text-muted-foreground">{formatDate(entry.created_at)}</span>
                </div>

                {entry.feature && (
                  <div className="mt-2 flex items-center gap-2 text-sm font-medium">
                    {entry.feature.title}
                    <FeatureStatusBadge status={entry.feature.status as FeatureStatus} />
                  </div>
                )}

                <p className="mt-2 text-sm whitespace-pre-wrap text-foreground/90">{entry.body}</p>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
