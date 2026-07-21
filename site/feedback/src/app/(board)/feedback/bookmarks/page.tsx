"use client";

import Link from "next/link";
import { Bookmark } from "lucide-react";
import { FeatureCard } from "@/components/feedback/FeatureCard";
import { EmptyState } from "@/components/feedback/EmptyState";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { useUser } from "@/lib/auth/useUser";
import { useBookmarkedFeatures } from "@/lib/queries/useBookmarks";

export default function BookmarksPage() {
  const { user, isLoading: userLoading } = useUser();
  const { data: features, isLoading } = useBookmarkedFeatures(user?.id);

  return (
    <div className="mx-auto max-w-3xl px-4 py-10">
      <div className="flex items-center gap-2">
        <Bookmark className="h-5 w-5 text-primary" />
        <h1 className="font-heading text-3xl font-bold tracking-tight">Your bookmarks</h1>
      </div>
      <p className="mt-1 text-sm text-muted-foreground">Requests you&apos;ve saved for later.</p>

      <div className="mt-6 flex flex-col gap-3">
        {userLoading || isLoading ? (
          Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-24 w-full rounded-xl" />)
        ) : !user ? (
          <EmptyState
            title="Sign in to see your bookmarks"
            description="Bookmarks are saved per account."
            action={<Button render={<Link href="/auth/sign-in?next=/feedback/bookmarks">Sign in</Link>} />}
          />
        ) : !features || features.length === 0 ? (
          <EmptyState
            title="No bookmarks yet"
            description="Tap the bookmark icon on any request to save it here."
          />
        ) : (
          features.map((feature) => <FeatureCard key={feature.id} feature={feature} />)
        )}
      </div>
    </div>
  );
}
