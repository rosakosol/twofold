"use client";

import { useState } from "react";
import Link from "next/link";
import { AlertTriangle, EyeOff, Pencil, RotateCcw } from "lucide-react";
import { StatusPill } from "@/components/site/StatusPill";
import { StatTiles } from "@/components/console/ConsoleUI";
import { GameChip } from "@/components/admin/games/GameChip";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useGameContentList, useGameDecks } from "@/lib/queries/useGameContent";
import {
  dismissalKey,
  useDismissDuplicatePair,
  useDuplicateDismissals,
  useRestoreDuplicatePair,
  type DismissalRow,
} from "@/lib/queries/useDuplicateDismissals";
import { ContentForm } from "@/components/admin/games/ContentForm";
import { CONTENT_TYPES, deckIdOf, type ContentRow, type ContentTypeConfig } from "@/lib/games/contentTypes";
import { findContentIssues, findSimilarPairs, type SimilarPair } from "@/lib/games/similarity";

/** Pairs shown before "Show N more pairs". */
const PAIRS_SHOWN = 5;

/** How alike a pair is: 75% and up in the error colour, 67% and up amber, the rest neutral. */
function SimilarityPill({ score, dismissed = false }: { score: number; dismissed?: boolean }) {
  const pct = Math.round(score * 100);
  const tone = dismissed ? "neutral" : score >= 0.75 ? "error" : score >= 0.67 ? "warning" : "neutral";
  return (
    <StatusPill tone={tone}>
      {score === 1 ? "Exact duplicate" : `${pct}% similar`}
      {dismissed ? ", dismissed" : ""}
    </StatusPill>
  );
}

interface DeckRef {
  label: string;
  /** null for entries with no deck_id, or a deck_id that isn't in this game type's deck
   * list — nothing to link to in either case. */
  id: string | null;
}

/** The deck an entry belongs to, linked through to that deck's page so a flagged entry
 * can be traced back to where it lives without hunting for it. */
function DeckLink({ deck }: { deck: DeckRef }) {
  if (!deck.id) return <p className="mt-1 text-xs text-muted-foreground">{deck.label}</p>;
  return (
    <Link
      href={`/admin/games/decks/${deck.id}`}
      className="mt-1 inline-block text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
    >
      {deck.label}
    </Link>
  );
}

function EntryCard({
  row,
  contentType,
  deck,
  onEdit,
}: {
  row: ContentRow;
  contentType: ContentTypeConfig;
  deck: DeckRef;
  onEdit: () => void;
}) {
  return (
    <div className="flex items-start justify-between gap-2 rounded-xl bg-[var(--surface-raised)] p-3">
      <div>
        <p className={`text-sm ${row.active ? "" : "text-muted-foreground line-through"}`}>
          {contentType.primaryText(row)}
        </p>
        <DeckLink deck={deck} />
      </div>
      <Button variant="ghost" size="icon-sm" className="shrink-0 text-muted-foreground" aria-label={`Edit "${contentType.primaryText(row)}"`} onClick={onEdit}>
        <Pencil className="h-4 w-4" />
      </Button>
    </div>
  );
}

/** Runs the similarity + structural-issue scan for one game type. A separate component (rather
 * than looping hooks inside a parent) so each game type owns its own query + edit-sheet state. */
function GameTypeChecker({ contentType }: { contentType: ContentTypeConfig }) {
  const { data: rows, isLoading } = useGameContentList(contentType.key);
  const { data: decks } = useGameDecks(contentType.gameType ?? undefined);
  const { data: dismissals, isLoading: dismissalsLoading } = useDuplicateDismissals(contentType.key);
  const dismiss = useDismissDuplicatePair(contentType.key);
  const restore = useRestoreDuplicatePair(contentType.key);
  const [editingRow, setEditingRow] = useState<ContentRow | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [showDismissed, setShowDismissed] = useState(false);
  const [showAllPairs, setShowAllPairs] = useState(false);

  if (isLoading || dismissalsLoading) return <Skeleton className="h-24 w-full rounded-lg" />;

  const allRows = rows ?? [];
  const allPairs = findSimilarPairs(allRows, contentType);
  const issues = findContentIssues(allRows, contentType);
  const deckTitleById = new Map((decks ?? []).map((d) => [d.id, `${d.emoji} ${d.title}`]));
  const deckFor = (row: ContentRow): DeckRef => {
    // Content from a deckless table always lands here, which is correct: the duplicate checker is
    // still useful for the daily bank, it just has no deck to attribute a row to.
    const deckId = deckIdOf(row);
    if (!deckId) return { label: "No deck", id: null };
    const label = deckTitleById.get(deckId);
    return label ? { label, id: deckId } : { label: "Unknown deck", id: null };
  };

  const dismissalByPairKey = new Map((dismissals ?? []).map((d) => [dismissalKey(d.row_a_id, d.row_b_id), d]));
  const activePairs = allPairs.filter((p) => !dismissalByPairKey.has(dismissalKey(p.a.id, p.b.id)));
  const dismissedPairs = allPairs.reduce<{ pair: SimilarPair; dismissal: DismissalRow }[]>((acc, pair) => {
    const dismissal = dismissalByPairKey.get(dismissalKey(pair.a.id, pair.b.id));
    if (dismissal) acc.push({ pair, dismissal });
    return acc;
  }, []);

  function edit(row: ContentRow) {
    setEditingRow(row);
    setFormOpen(true);
  }

  if (activePairs.length === 0 && issues.length === 0 && dismissedPairs.length === 0) {
    return (
      <p className="console-empty is-success text-sm">
        No similarity or content issues found. {allRows.length} entries checked.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-5">
      <StatTiles
        items={[
          { label: "Entries checked", value: allRows.length },
          { label: "Similar pairs", value: activePairs.length },
          { label: "Content issues", value: issues.length },
        ]}
      />

      {activePairs.length > 0 && (
        <div>
          <div className="flex flex-col gap-2">
            {(showAllPairs ? activePairs : activePairs.slice(0, PAIRS_SHOWN)).map(({ a, b, score }) => (
              <div key={`${a.id}-${b.id}`} className="console-card p-3">
                <div className="mb-2 flex items-center justify-between">
                  <SimilarityPill score={score} />
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 gap-1 text-xs text-muted-foreground"
                    disabled={dismiss.isPending}
                    onClick={() => dismiss.mutate({ idA: a.id, idB: b.id })}
                  >
                    <EyeOff className="h-3.5 w-3.5" aria-hidden /> Not a duplicate
                  </Button>
                </div>
                <div className="grid gap-2 sm:grid-cols-2">
                  <EntryCard row={a} contentType={contentType} deck={deckFor(a)} onEdit={() => edit(a)} />
                  <EntryCard row={b} contentType={contentType} deck={deckFor(b)} onEdit={() => edit(b)} />
                </div>
              </div>
            ))}
          </div>
          {activePairs.length > PAIRS_SHOWN && (
            <Button variant="outline" size="sm" className="mt-3" onClick={() => setShowAllPairs((v) => !v)}>
              {showAllPairs ? "Show fewer pairs" : `Show ${activePairs.length - PAIRS_SHOWN} more pairs`}
            </Button>
          )}
        </div>
      )}

      {dismissedPairs.length > 0 && (
        <div>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 px-0 text-xs text-muted-foreground"
            onClick={() => setShowDismissed((v) => !v)}
          >
            {showDismissed ? "Hide" : "Show"} {dismissedPairs.length} dismissed pair{dismissedPairs.length === 1 ? "" : "s"}
          </Button>
          {showDismissed && (
            <div className="mt-2 flex flex-col gap-2">
              {dismissedPairs.map(({ pair: { a, b, score }, dismissal }) => (
                <div key={dismissal.id} className="rounded-2xl border border-dashed border-[var(--line-strong)] p-3 opacity-75">
                  <div className="mb-2 flex items-center justify-between">
                    <SimilarityPill score={score} dismissed />
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-7 gap-1 text-xs text-muted-foreground"
                      disabled={restore.isPending}
                      onClick={() => restore.mutate(dismissal.id)}
                    >
                      <RotateCcw className="h-3.5 w-3.5" /> Restore
                    </Button>
                  </div>
                  <div className="grid gap-2 sm:grid-cols-2">
                    <EntryCard row={a} contentType={contentType} deck={deckFor(a)} onEdit={() => edit(a)} />
                    <EntryCard row={b} contentType={contentType} deck={deckFor(b)} onEdit={() => edit(b)} />
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {issues.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-medium text-muted-foreground">
            {issues.length} content issue{issues.length === 1 ? "" : "s"}
          </p>
          <div className="flex flex-col gap-2">
            {issues.map(({ row, reason }, i) => (
              <div key={`${row.id}-${i}`} className="console-card flex items-start justify-between gap-2 p-3">
                <div>
                  <p className={`text-sm ${row.active ? "" : "text-muted-foreground line-through"}`}>
                    {contentType.primaryText(row)}
                  </p>
                  <DeckLink deck={deckFor(row)} />
                  <p className="mt-1 flex items-center gap-1 text-xs text-[var(--warning)]">
                    <AlertTriangle className="h-3 w-3 shrink-0" aria-hidden /> {reason}
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="shrink-0 text-muted-foreground"
                  aria-label={`Edit "${contentType.primaryText(row)}"`}
                  onClick={() => edit(row)}
                >
                  <Pencil className="h-4 w-4" />
                </Button>
              </div>
            ))}
          </div>
        </div>
      )}

      <ContentForm
        contentType={contentType}
        decks={decks ?? []}
        editingRow={editingRow}
        open={formOpen}
        onOpenChange={setFormOpen}
      />
    </div>
  );
}

export function DuplicateChecker() {
  return (
    <div className="flex flex-col gap-8">
      <p className="text-sm text-muted-foreground">
        Scans each game type for near-duplicate wording and structural problems: trivia answers missing
        from their options, identical this-or-that choices, blank or placeholder text. Comparisons only
        run within a game type, not across them.
      </p>
      {CONTENT_TYPES.map((c) => (
        <div key={c.key}>
          <h2 className="mb-3 flex items-center gap-2 text-base font-semibold">
            <GameChip gameType={c.gameType} />
            {c.label}
          </h2>
          <GameTypeChecker contentType={c} />
        </div>
      ))}
    </div>
  );
}
