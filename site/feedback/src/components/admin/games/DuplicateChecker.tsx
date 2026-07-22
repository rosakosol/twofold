"use client";

import { useState } from "react";
import { AlertTriangle, EyeOff, Pencil, RotateCcw } from "lucide-react";
import { Badge } from "@/components/ui/badge";
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
import { CONTENT_TYPES, type ContentRow, type ContentTypeConfig } from "@/lib/games/contentTypes";
import { findContentIssues, findSimilarPairs, type SimilarPair } from "@/lib/games/similarity";

function EntryCard({
  row,
  contentType,
  deckTitle,
  onEdit,
}: {
  row: ContentRow;
  contentType: ContentTypeConfig;
  deckTitle: string;
  onEdit: () => void;
}) {
  return (
    <div className="flex items-start justify-between gap-2 rounded-md bg-muted/30 p-2">
      <div>
        <p className={`text-sm ${row.active ? "" : "text-muted-foreground line-through"}`}>
          {contentType.primaryText(row)}
        </p>
        <p className="mt-1 text-xs text-muted-foreground">{deckTitle}</p>
      </div>
      <Button variant="ghost" size="icon-sm" className="shrink-0 text-muted-foreground" aria-label="Edit" onClick={onEdit}>
        <Pencil className="h-4 w-4" />
      </Button>
    </div>
  );
}

/** Runs the similarity + structural-issue scan for one game type. A separate component (rather
 * than looping hooks inside a parent) so each game type owns its own query + edit-sheet state. */
function GameTypeChecker({ contentType }: { contentType: ContentTypeConfig }) {
  const { data: rows, isLoading } = useGameContentList(contentType.key);
  const { data: decks } = useGameDecks(contentType.gameType);
  const { data: dismissals, isLoading: dismissalsLoading } = useDuplicateDismissals(contentType.key);
  const dismiss = useDismissDuplicatePair(contentType.key);
  const restore = useRestoreDuplicatePair(contentType.key);
  const [editingRow, setEditingRow] = useState<ContentRow | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [showDismissed, setShowDismissed] = useState(false);

  if (isLoading || dismissalsLoading) return <Skeleton className="h-24 w-full rounded-lg" />;

  const allRows = rows ?? [];
  const allPairs = findSimilarPairs(allRows, contentType);
  const issues = findContentIssues(allRows, contentType);
  const deckTitleById = new Map((decks ?? []).map((d) => [d.id, `${d.emoji} ${d.title}`]));
  const deckTitleFor = (row: ContentRow) => (row.deck_id ? (deckTitleById.get(row.deck_id) ?? "Unknown deck") : "No deck");

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
      <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
        No similarity or content issues found — {allRows.length} entries checked.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-5">
      {activePairs.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-medium text-muted-foreground">
            {activePairs.length} similar/duplicate pair{activePairs.length === 1 ? "" : "s"}
          </p>
          <div className="flex flex-col gap-2">
            {activePairs.map(({ a, b, score }) => (
              <div key={`${a.id}-${b.id}`} className="rounded-lg border p-3">
                <div className="mb-2 flex items-center justify-between">
                  <Badge variant={score === 1 ? "default" : "secondary"}>
                    {score === 1 ? "Exact duplicate" : `${Math.round(score * 100)}% similar`}
                  </Badge>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 gap-1 text-xs text-muted-foreground"
                    disabled={dismiss.isPending}
                    onClick={() => dismiss.mutate({ idA: a.id, idB: b.id })}
                  >
                    <EyeOff className="h-3.5 w-3.5" /> Not a duplicate
                  </Button>
                </div>
                <div className="grid gap-2 sm:grid-cols-2">
                  <EntryCard row={a} contentType={contentType} deckTitle={deckTitleFor(a)} onEdit={() => edit(a)} />
                  <EntryCard row={b} contentType={contentType} deckTitle={deckTitleFor(b)} onEdit={() => edit(b)} />
                </div>
              </div>
            ))}
          </div>
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
                <div key={dismissal.id} className="rounded-lg border border-dashed p-3 opacity-75">
                  <div className="mb-2 flex items-center justify-between">
                    <Badge variant="outline">
                      {score === 1 ? "Exact duplicate" : `${Math.round(score * 100)}% similar`} — dismissed
                    </Badge>
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
                    <EntryCard row={a} contentType={contentType} deckTitle={deckTitleFor(a)} onEdit={() => edit(a)} />
                    <EntryCard row={b} contentType={contentType} deckTitle={deckTitleFor(b)} onEdit={() => edit(b)} />
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
              <div key={`${row.id}-${i}`} className="flex items-start justify-between gap-2 rounded-lg border p-3">
                <div>
                  <p className={`text-sm ${row.active ? "" : "text-muted-foreground line-through"}`}>
                    {contentType.primaryText(row)}
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">{deckTitleFor(row)}</p>
                  <p className="mt-1 flex items-center gap-1 text-xs text-amber-600 dark:text-amber-500">
                    <AlertTriangle className="h-3 w-3 shrink-0" /> {reason}
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="shrink-0 text-muted-foreground"
                  aria-label="Edit"
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
        Scans each game type for near-duplicate wording and structural problems — trivia answers
        missing from their options, identical this-or-that choices, blank or placeholder text.
        Comparisons only run within a game type, not across them.
      </p>
      {CONTENT_TYPES.map((c) => (
        <div key={c.key}>
          <h2 className="mb-3 text-sm font-semibold text-muted-foreground">{c.label}</h2>
          <GameTypeChecker contentType={c} />
        </div>
      ))}
    </div>
  );
}
