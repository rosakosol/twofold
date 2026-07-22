"use client";

import { useState } from "react";
import { AlertTriangle, Pencil } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useGameContentList, useGameDecks } from "@/lib/queries/useGameContent";
import { ContentForm } from "@/components/admin/games/ContentForm";
import { CONTENT_TYPES, type ContentRow, type ContentTypeConfig } from "@/lib/games/contentTypes";
import { findContentIssues, findSimilarPairs } from "@/lib/games/similarity";

function EntryCard({ row, contentType, onEdit }: { row: ContentRow; contentType: ContentTypeConfig; onEdit: () => void }) {
  return (
    <div className="flex items-start justify-between gap-2 rounded-md bg-muted/30 p-2">
      <p className={`text-sm ${row.active ? "" : "text-muted-foreground line-through"}`}>
        {contentType.primaryText(row)}
      </p>
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
  const [editingRow, setEditingRow] = useState<ContentRow | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  if (isLoading) return <Skeleton className="h-24 w-full rounded-lg" />;

  const allRows = rows ?? [];
  const pairs = findSimilarPairs(allRows, contentType);
  const issues = findContentIssues(allRows, contentType);

  function edit(row: ContentRow) {
    setEditingRow(row);
    setFormOpen(true);
  }

  if (pairs.length === 0 && issues.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
        No similarity or content issues found — {allRows.length} entries checked.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-5">
      {pairs.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-medium text-muted-foreground">
            {pairs.length} similar/duplicate pair{pairs.length === 1 ? "" : "s"}
          </p>
          <div className="flex flex-col gap-2">
            {pairs.map(({ a, b, score }) => (
              <div key={`${a.id}-${b.id}`} className="rounded-lg border p-3">
                <Badge variant={score === 1 ? "default" : "secondary"} className="mb-2">
                  {score === 1 ? "Exact duplicate" : `${Math.round(score * 100)}% similar`}
                </Badge>
                <div className="grid gap-2 sm:grid-cols-2">
                  <EntryCard row={a} contentType={contentType} onEdit={() => edit(a)} />
                  <EntryCard row={b} contentType={contentType} onEdit={() => edit(b)} />
                </div>
              </div>
            ))}
          </div>
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
