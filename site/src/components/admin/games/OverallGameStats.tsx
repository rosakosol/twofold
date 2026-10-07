"use client";

import { useGameDecks, useGameContentTiers } from "@/lib/queries/useGameContent";
import { StatTiles } from "@/components/console/ConsoleUI";
import { GameChip, gameGradient } from "@/components/admin/games/GameChip";
import { DECK_CONTENT_TYPES, type TieredContentTypeKey } from "@/lib/games/contentTypes";
import { Skeleton } from "@/components/ui/skeleton";

/** Games hub's "Overall" tab — aggregates across every game type at once. The four content
 * tables each get their own hook call (rather than looping DECK_CONTENT_TYPES through one call)
 * since DECK_CONTENT_TYPES is a fixed, known set and React hooks can't be called from a loop/map. */
export function OverallGameStats() {
  const { data: decks, isLoading: decksLoading } = useGameDecks();
  const deepConversations = useGameContentTiers("deep_conversation_topics");
  const moreLikely = useGameContentTiers("more_likely_prompts");
  const thisOrThat = useGameContentTiers("this_or_that_prompts");
  const trivia = useGameContentTiers("trivia_questions");

  // Keyed by the tiered types only — the daily question bank has no tier to summarise.
  const byKey: Record<TieredContentTypeKey, { data?: { tier: string }[]; isLoading: boolean }> = {
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

  const split = (label: string, plus: number, premium: number) => {
    const total = plus + premium;
    const plusPct = total ? (plus / total) * 100 : 0;
    return (
      <div className="console-card console-card-pad">
        <h3 className="text-sm font-semibold">{label}</h3>
        <div
          className="split-bar mt-3"
          role="img"
          aria-label={`${label}: ${plus} Plus, ${premium} Premium`}
        >
          <span style={{ width: `${plusPct}%` }} />
          <span style={{ width: `${total ? 100 - plusPct : 0}%` }} />
        </div>
        <div className="split-legend">
          <span>
            <span className="split-key" style={{ background: "var(--accent)" }} />
            Plus <b>{plus}</b>
          </span>
          <span>
            <span className="split-key" style={{ background: "var(--indigo)" }} />
            Premium <b>{premium}</b>
          </span>
        </div>
      </div>
    );
  };

  return (
    <div className="flex flex-col gap-6">
      <StatTiles
        items={[
          { label: "Total decks", value: totalDecks },
          { label: "Total questions", value: totalQuestions },
        ]}
      />

      <div>
        <h2 className="mb-3 text-sm font-semibold text-muted-foreground">By tier</h2>
        <div className="games-grid">
          {split("Decks", plusDecks, premiumDecks)}
          {split("Questions", plusQuestions, premiumQuestions)}
        </div>
      </div>

      <div>
        <h2 className="mb-3 text-sm font-semibold text-muted-foreground">By game type</h2>
        <div className="console-table-wrap">
          <table className="console-table">
            <thead>
              <tr>
                <th scope="col">Game type</th>
                <th scope="col">Decks</th>
                <th scope="col">Questions</th>
                <th scope="col">Share of questions</th>
              </tr>
            </thead>
            <tbody>
              {DECK_CONTENT_TYPES.map((c) => {
                const questions = byKey[c.key as TieredContentTypeKey].data?.length ?? 0;
                const share = totalQuestions ? Math.round((questions / totalQuestions) * 100) : 0;
                return (
                  <tr key={c.key}>
                    <td>
                      <span className="inline-flex items-center gap-2 font-semibold">
                        <GameChip gameType={c.gameType} />
                        {c.label}
                      </span>
                    </td>
                    <td className="num">{decks?.filter((d) => d.game_type === c.gameType).length ?? 0}</td>
                    <td className="num">{questions}</td>
                    <td>
                      <span className="flex items-center gap-3">
                        <span className="share-bar" role="img" aria-label={`${share}% of all questions`}>
                          <span style={{ width: `${share}%`, background: gameGradient(c.gameType) }} />
                        </span>
                        <span className="num muted w-10 text-right">{share}%</span>
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
