"use client";

import { useState } from "react";
import { toast } from "sonner";
import { ChevronLeft, ChevronRight, Pencil, Trash2, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StatusPill } from "@/components/site/StatusPill";
import { ConsoleEmpty } from "@/components/console/ConsoleUI";
import { Switch } from "@/components/ui/switch";
import { Skeleton } from "@/components/ui/skeleton";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { useGameContentForDeck, useGameContentPage, useGameDecks } from "@/lib/queries/useGameContent";
import { useDeleteContent, useUpdateContent } from "@/lib/queries/useGameContentMutations";
import { ContentForm } from "@/components/admin/games/ContentForm";
import { deckIdOf, tierOf } from "@/lib/games/contentTypes";
import type { ContentRow, ContentTypeConfig, TieredContentTypeKey } from "@/lib/games/contentTypes";

/** Enough to scan a category without scrolling forever; the daily question bank alone is over a
 * thousand entries, and rendering them all meant a thousand switches on one page. */
const PAGE_SIZE = 50;

function DeleteButton({ contentType, row }: { contentType: ContentTypeConfig; row: ContentRow }) {
  const [open, setOpen] = useState(false);
  const del = useDeleteContent(contentType.key);

  async function handleConfirm() {
    try {
      await del.mutateAsync(row.id);
      toast.success("Deleted");
      setOpen(false);
    } catch {
      toast.error("Couldn't delete this entry.");
    }
  }

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger
        render={
          <Button variant="ghost" size="icon-sm" className="text-muted-foreground hover:text-destructive" aria-label="Delete this entry">
            <Trash2 className="h-4 w-4" aria-hidden />
          </Button>
        }
      />
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete this {contentType.label.toLowerCase()} entry?</AlertDialogTitle>
          <AlertDialogDescription>
            &ldquo;{contentType.primaryText(row)}&rdquo; will be permanently removed. This can&apos;t be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={handleConfirm}
            disabled={del.isPending}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            Delete
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function ActiveToggle({ contentType, row }: { contentType: ContentTypeConfig; row: ContentRow }) {
  const update = useUpdateContent(contentType.key);
  return (
    <Switch
      aria-label="Active"
      checked={row.active}
      disabled={update.isPending}
      onCheckedChange={(checked) =>
        update.mutate(
          { id: row.id, patch: { active: checked } as never },
          { onError: () => toast.error("Couldn't update.") }
        )
      }
    />
  );
}

export function ContentTable({
  contentType,
  deckFilter,
}: {
  contentType: ContentTypeConfig;
  /** Scope the list to one deck's questions — used by the deck detail view. */
  deckFilter?: string;
}) {
  const [page, setPage] = useState(0);
  // A deck is at most a dozen questions, so it loads whole; only the full table pages.
  // Only deck-backed types are ever opened with a deckFilter; the daily bank has no deck_id.
  const deckQuery = useGameContentForDeck(contentType.key as TieredContentTypeKey, deckFilter);
  const pageQuery = useGameContentPage(contentType.key, page, PAGE_SIZE, !deckFilter);
  const { data: decks } = useGameDecks(contentType.gameType ?? undefined);
  const [editingRow, setEditingRow] = useState<ContentRow | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  const isLoading = deckFilter ? deckQuery.isLoading : pageQuery.isLoading;
  const rows = deckFilter ? deckQuery.data : pageQuery.data?.rows;
  const total = deckFilter ? (deckQuery.data?.length ?? 0) : (pageQuery.data?.total ?? 0);
  const lastPage = Math.max(0, Math.ceil(total / PAGE_SIZE) - 1);
  // Deleting the last entry on the last page would otherwise strand the view on an empty page.
  if (!deckFilter && page > lastPage && pageQuery.data) setPage(lastPage);
  const deckTitleById = new Map((decks ?? []).map((d) => [d.id, `${d.emoji} ${d.title}`]));
  // In a deck's own view, category and tier come from the deck, so a row only says so when it
  // differs (docs/TWOFOLD_WEBSITE.md, section 9.2).
  const parentDeck = deckFilter ? (decks ?? []).find((d) => d.id === deckFilter) : undefined;
  const inDeck = Boolean(deckFilter);

  if (isLoading) return <Skeleton className="h-64 w-full rounded-lg" />;

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm text-muted-foreground">{total.toLocaleString()} entries</p>
        <Button
          size="sm"
          onClick={() => {
            setEditingRow(null);
            setFormOpen(true);
          }}
        >
          <Plus className="h-4 w-4" aria-hidden /> New entry
        </Button>
      </div>

      {!rows || rows.length === 0 ? (
        <ConsoleEmpty title="No entries yet" />
      ) : (
        <div className="console-table-wrap">
          <table className="console-table">
            <thead>
              <tr>
                {inDeck && <th scope="col">#</th>}
                <th scope="col">{inDeck ? "Question" : contentType.label}</th>
                {!inDeck && <th scope="col">Category</th>}
                {!inDeck && <th scope="col">Tier</th>}
                {!inDeck && <th scope="col">Deck</th>}
                <th scope="col">Active</th>
                <th scope="col">
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => {
                const tier = tierOf(row);
                const otherCategory = parentDeck && row.category && row.category !== parentDeck.topic;
                const otherTier = parentDeck && tier && tier !== parentDeck.tier;
                return (
                <tr key={row.id} className={row.active ? undefined : "opacity-50"}>
                  {inDeck && <td className="num muted">{index + 1}</td>}
                  <td className="max-w-[36rem]">
                    <span className="block truncate">{contentType.primaryText(row)}</span>
                    {(otherCategory || otherTier) && (
                      <span className="mt-1 flex flex-wrap gap-1">
                        {otherCategory && <span className="pill pill-warning">Category: {row.category}</span>}
                        {otherTier && <span className="pill pill-warning">Tier: {tier === "premium" ? "Premium" : "Plus"}</span>}
                      </span>
                    )}
                  </td>
                  {!inDeck && <td className="muted">{row.category}</td>}
                  {!inDeck && (
                    <td>
                      {tier ? (
                        <StatusPill tone={tier === "premium" ? "indigo" : "accent"}>{tier === "premium" ? "Premium" : "Plus"}</StatusPill>
                      ) : null}
                    </td>
                  )}
                  {!inDeck && (
                    <td className="whitespace-nowrap">
                      {deckIdOf(row) ? (deckTitleById.get(deckIdOf(row)!) ?? "None") : "None"}
                    </td>
                  )}
                  <td>
                    <ActiveToggle contentType={contentType} row={row} />
                  </td>
                  <td>
                    <div className="flex items-center justify-end gap-1">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="text-muted-foreground"
                        aria-label={`Edit "${contentType.primaryText(row)}"`}
                        onClick={() => {
                          setEditingRow(row);
                          setFormOpen(true);
                        }}
                      >
                        <Pencil className="h-4 w-4" aria-hidden />
                      </Button>
                      <DeleteButton contentType={contentType} row={row} />
                    </div>
                  </td>
                </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {!deckFilter && total > PAGE_SIZE && (
        <div className="console-pager">
          <p className="num">
            Showing {page * PAGE_SIZE + 1} to {Math.min((page + 1) * PAGE_SIZE, total)} of {total.toLocaleString()}
          </p>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              disabled={page === 0 || pageQuery.isFetching}
              onClick={() => setPage((p) => Math.max(0, p - 1))}
            >
              <ChevronLeft className="h-4 w-4" aria-hidden />
              Previous
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={page >= lastPage || pageQuery.isFetching}
              onClick={() => setPage((p) => p + 1)}
            >
              Next
              <ChevronRight className="h-4 w-4" aria-hidden />
            </Button>
          </div>
        </div>
      )}

      <ContentForm
        contentType={contentType}
        decks={decks ?? []}
        editingRow={editingRow}
        open={formOpen}
        onOpenChange={setFormOpen}
        defaultDeckId={deckFilter}
      />
    </div>
  );
}
