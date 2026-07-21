"use client";

import { useGameDecks, useGameContentTiers } from "@/lib/queries/useGameContent";
import { StatCard } from "@/components/admin/games/GameTypeStats";
import { CONTENT_TYPES, type ContentTypeKey } from "@/lib/games/contentTypes";
import { Skeleton } from "@/components/ui/skeleton";

/** Games hub's "Overall" tab — aggregates across every game type at once. The four content
 * tables each get their own hook call (rather than looping CONTENT_TYPES through one call)
 * since CONTENT_TYPES is a fixed, known set and React hooks can't be called from a loop/map. */
export function OverallGameStats() {
  const { data: decks, isLoading: decksLoading } = useGameDecks();
  const deepConversations = useGameContentTiers("deep_conversation_topics");
  const moreLikely = useGameContentTiers("more_likely_prompts");
  const thisOrThat = useGameContentTiers("this_or_that_prompts");
  const trivia = useGameContentTiers("trivia_questions");

  const byKey: Record<ContentTypeKey, { data?: { tier: string }[]; isLoading: boolean }> = {
    deep_conversation_topics: deepConversations,
    more_likely_prompts: moreLikely,
    this_or_that_prompts: thisOrThat,
    trivia_questions: trivia,
  };

  const contentLoading = Object.values(byKey).some((q) => q.isLoading);
  if (decksLoading || contentLoading) return <Skeleton className="h-64 w-full rounded-lg" />;

  const allRows = Object.values(byKey).flatMap((q) => q.data ?? []);

  const totalDecks = decks?.length ?? 0;
  const totalQuestions = allRows.length;
  const plusDecks = decks?.filter((d) => d.tier === "plus").length ?? 0;
  const premiumDecks = decks?.filter((d) => d.tier === "premium").length ?? 0;
  const plusQuestions = allRows.filter((r) => r.tier === "plus").length;
  const premiumQuestions = allRows.filter((r) => r.tier === "premium").length;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h2 className="mb-3 text-sm font-semibold text-muted-foreground">Overall</h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-2">
          <StatCard label="Total decks" value={String(totalDecks)} />
          <StatCard label="Total questions" value={String(totalQuestions)} />
        </div>
      </div>

      <div>
        <h2 className="mb-3 text-sm font-semibold text-muted-foreground">By tier</h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <StatCard label="Plus decks" value={String(plusDecks)} />
          <StatCard label="Premium decks" value={String(premiumDecks)} />
          <StatCard label="Plus questions" value={String(plusQuestions)} />
          <StatCard label="Premium questions" value={String(premiumQuestions)} />
        </div>
      </div>

      <div>
        <h2 className="mb-3 text-sm font-semibold text-muted-foreground">By game type</h2>
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/50 text-left text-xs text-muted-foreground">
              <tr>
                <th className="px-3 py-2 font-medium">Game type</th>
                <th className="px-3 py-2 font-medium">Decks</th>
                <th className="px-3 py-2 font-medium">Questions</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {CONTENT_TYPES.map((c) => (
                <tr key={c.key}>
                  <td className="px-3 py-2 font-medium">{c.label}</td>
                  <td className="px-3 py-2 tabular-nums">
                    {decks?.filter((d) => d.game_type === c.gameType).length ?? 0}
                  </td>
                  <td className="px-3 py-2 tabular-nums">{byKey[c.key].data?.length ?? 0}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
