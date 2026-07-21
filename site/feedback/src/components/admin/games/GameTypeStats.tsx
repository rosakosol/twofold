"use client";

import Link from "next/link";
import { Library, ListChecks, ChevronRight } from "lucide-react";
import { useGameDecks, useGameContentTiers } from "@/lib/queries/useGameContent";
import type { ContentTypeConfig } from "@/lib/games/contentTypes";
import { Skeleton } from "@/components/ui/skeleton";

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border bg-muted/30 px-4 py-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
    </div>
  );
}

function formatRatio(plus: number, premium: number): string {
  if (plus === 0 && premium === 0) return "—";
  if (premium === 0) return `${plus}:0`;
  return `${(plus / premium).toFixed(2)}:1`;
}

function NavCard({
  href,
  icon: Icon,
  title,
  count,
  countLabel,
}: {
  href: string;
  icon: typeof Library;
  title: string;
  count: number;
  countLabel: string;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-4 rounded-lg border bg-card p-4 transition-colors hover:bg-muted/50"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
        <Icon className="h-5 w-5" />
      </div>
      <div className="flex-1">
        <p className="font-semibold">{title}</p>
        <p className="text-sm text-muted-foreground">
          {count} {countLabel}
        </p>
      </div>
      <ChevronRight className="h-4 w-4 text-muted-foreground" />
    </Link>
  );
}

/** Fetches once (via TanStack Query's shared cache) and drives both the summary stat cards
 * and the two nav cards — the actual deck/entry tables only mount once you click through, so
 * opening /admin/games never pulls every game type's full question list at once. */
export function GameTypeStats({ contentType }: { contentType: ContentTypeConfig }) {
  const { data: decks, isLoading: decksLoading } = useGameDecks(contentType.gameType);
  const { data: rows, isLoading: rowsLoading } = useGameContentTiers(contentType.key);

  if (decksLoading || rowsLoading) return <Skeleton className="h-40 w-full rounded-lg" />;

  const totalDecks = decks?.length ?? 0;
  const totalQuestions = rows?.length ?? 0;
  const plusDeckList = decks?.filter((d) => d.tier === "plus") ?? [];
  const premiumDeckList = decks?.filter((d) => d.tier === "premium") ?? [];
  const plusDecks = plusDeckList.length;
  const premiumDecks = premiumDeckList.length;
  const plusQuestions = rows?.filter((r) => r.tier === "plus").length ?? 0;
  const premiumQuestions = rows?.filter((r) => r.tier === "premium").length ?? 0;
  // Derived from game_decks.question_count (trigger-maintained) rather than the content
  // table's tier counts, since content rows can have a null deck_id and skew a tier-count-based average.
  const avgPerPlusDeck =
    plusDecks > 0 ? (plusDeckList.reduce((sum, d) => sum + d.question_count, 0) / plusDecks).toFixed(1) : "0";
  const avgPerPremiumDeck =
    premiumDecks > 0
      ? (premiumDeckList.reduce((sum, d) => sum + d.question_count, 0) / premiumDecks).toFixed(1)
      : "0";

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label="Decks" value={String(totalDecks)} />
        <StatCard label="Questions" value={String(totalQuestions)} />
        <StatCard label="Plus decks" value={String(plusDecks)} />
        <StatCard label="Premium decks" value={String(premiumDecks)} />
        <StatCard label="Avg / plus deck" value={avgPerPlusDeck} />
        <StatCard label="Avg / premium deck" value={avgPerPremiumDeck} />
        <StatCard label="Plus : Premium decks" value={formatRatio(plusDecks, premiumDecks)} />
        <StatCard label="Plus : Premium questions" value={formatRatio(plusQuestions, premiumQuestions)} />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <NavCard
          href={`/admin/games/${contentType.key}/decks`}
          icon={Library}
          title="Decks"
          count={totalDecks}
          countLabel="decks"
        />
        <NavCard
          href={`/admin/games/${contentType.key}/entries`}
          icon={ListChecks}
          title={`All ${contentType.label} entries`}
          count={totalQuestions}
          countLabel="entries"
        />
      </div>
    </div>
  );
}
