"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Pencil, Trash2, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
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
import { useGameContentList, useGameDecks } from "@/lib/queries/useGameContent";
import { useDeleteContent, useUpdateContent } from "@/lib/queries/useGameContentMutations";
import { ContentForm } from "@/components/admin/games/ContentForm";
import type { ContentRow, ContentTypeConfig } from "@/lib/games/contentTypes";

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
          <Button variant="ghost" size="icon-sm" className="text-muted-foreground hover:text-destructive">
            <Trash2 className="h-4 w-4" />
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
  const { data: allRows, isLoading } = useGameContentList(contentType.key);
  const { data: decks } = useGameDecks(contentType.gameType);
  const [editingRow, setEditingRow] = useState<ContentRow | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  const rows = deckFilter ? (allRows ?? []).filter((r) => r.deck_id === deckFilter) : allRows;
  const deckTitleById = new Map((decks ?? []).map((d) => [d.id, `${d.emoji} ${d.title}`]));

  if (isLoading) return <Skeleton className="h-64 w-full rounded-lg" />;

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm text-muted-foreground">{rows?.length ?? 0} entries</p>
        <Button
          size="sm"
          onClick={() => {
            setEditingRow(null);
            setFormOpen(true);
          }}
        >
          <Plus className="h-4 w-4" /> New
        </Button>
      </div>

      {!rows || rows.length === 0 ? (
        <p className="py-12 text-center text-sm text-muted-foreground">No entries yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/50 text-left text-xs text-muted-foreground">
              <tr>
                <th className="px-3 py-2 font-medium">{contentType.label}</th>
                <th className="px-3 py-2 font-medium">Category</th>
                <th className="px-3 py-2 font-medium">Tier</th>
                {!deckFilter && <th className="px-3 py-2 font-medium">Deck</th>}
                <th className="px-3 py-2 font-medium">Active</th>
                <th className="px-3 py-2 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {rows.map((row) => (
                <tr key={row.id} className={row.active ? undefined : "opacity-50"}>
                  <td className="max-w-96 truncate px-3 py-2">{contentType.primaryText(row)}</td>
                  <td className="px-3 py-2">{row.category}</td>
                  <td className="px-3 py-2">
                    <Badge variant={row.tier === "premium" ? "default" : "secondary"}>{row.tier}</Badge>
                  </td>
                  {!deckFilter && (
                    <td className="px-3 py-2 whitespace-nowrap">
                      {row.deck_id ? (deckTitleById.get(row.deck_id) ?? "—") : "—"}
                    </td>
                  )}
                  <td className="px-3 py-2">
                    <ActiveToggle contentType={contentType} row={row} />
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-1">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="text-muted-foreground"
                        aria-label="Edit"
                        onClick={() => {
                          setEditingRow(row);
                          setFormOpen(true);
                        }}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <DeleteButton contentType={contentType} row={row} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
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
