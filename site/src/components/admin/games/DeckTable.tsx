"use client";

import { useState } from "react";
import Link from "next/link";
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
import { useGameDecks } from "@/lib/queries/useGameContent";
import { useDeleteDeck, useUpdateDeck } from "@/lib/queries/useGameContentMutations";
import { DeckForm } from "@/components/admin/games/DeckForm";
import { CONTENT_TYPES, type GameDeck, type GameType } from "@/lib/games/contentTypes";

const LABEL_BY_GAME_TYPE = new Map(CONTENT_TYPES.map((c) => [c.gameType, c.label]));

function DeleteButton({ deck }: { deck: GameDeck }) {
  const [open, setOpen] = useState(false);
  const del = useDeleteDeck();

  async function handleConfirm() {
    try {
      const { questions_deleted, sessions_deleted } = await del.mutateAsync(deck.id);
      toast.success(
        `Deleted "${deck.title}" and ${questions_deleted} ${questions_deleted === 1 ? "question" : "questions"}` +
          (sessions_deleted > 0
            ? `, plus ${sessions_deleted} ${sessions_deleted === 1 ? "session" : "sessions"} played from it.`
            : "."),
      );
      setOpen(false);
    } catch {
      toast.error("Couldn't delete this deck.");
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
          <AlertDialogTitle>Delete &ldquo;{deck.title}&rdquo;?</AlertDialogTitle>
          <AlertDialogDescription>
            This deletes the deck&apos;s {deck.question_count}{" "}
            {deck.question_count === 1 ? "question" : "questions"} along with it, and any sessions
            couples have played from it. Questions that belong to no deck are untouched. This
            can&apos;t be undone &mdash; to keep the questions, reassign them to another deck first.
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

function ActiveToggle({ deck }: { deck: GameDeck }) {
  const update = useUpdateDeck();
  return (
    <Switch
      checked={deck.active}
      disabled={update.isPending}
      onCheckedChange={(checked) =>
        update.mutate({ id: deck.id, patch: { active: checked } }, { onError: () => toast.error("Couldn't update.") })
      }
    />
  );
}

export function DeckTable({ gameType }: { gameType?: GameType }) {
  const { data: decks, isLoading } = useGameDecks(gameType);
  const [editingDeck, setEditingDeck] = useState<GameDeck | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  if (isLoading) return <Skeleton className="h-64 w-full rounded-lg" />;

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm text-muted-foreground">{decks?.length ?? 0} decks</p>
        <Button
          size="sm"
          onClick={() => {
            setEditingDeck(null);
            setFormOpen(true);
          }}
        >
          <Plus className="h-4 w-4" /> New
        </Button>
      </div>

      {!decks || decks.length === 0 ? (
        <p className="py-12 text-center text-sm text-muted-foreground">No decks yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/50 text-left text-xs text-muted-foreground">
              <tr>
                <th className="px-3 py-2 font-medium">Deck</th>
                {!gameType && <th className="px-3 py-2 font-medium">Game type</th>}
                <th className="px-3 py-2 font-medium">Tier</th>
                <th className="px-3 py-2 font-medium">Questions</th>
                <th className="px-3 py-2 font-medium">Sort</th>
                <th className="px-3 py-2 font-medium">Active</th>
                <th className="px-3 py-2 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {decks.map((deck) => (
                <tr key={deck.id} className={deck.active ? undefined : "opacity-50"}>
                  <td className="px-3 py-2">
                    <Link href={`/admin/games/decks/${deck.id}`} className="font-medium hover:underline">
                      {deck.emoji} {deck.title}
                    </Link>
                    <span className="ml-1 text-xs text-muted-foreground">({deck.topic})</span>
                  </td>
                  {!gameType && (
                    <td className="px-3 py-2">{LABEL_BY_GAME_TYPE.get(deck.game_type) ?? deck.game_type}</td>
                  )}
                  <td className="px-3 py-2">
                    <Badge variant={deck.tier === "premium" ? "default" : "secondary"}>{deck.tier}</Badge>
                  </td>
                  <td className="px-3 py-2 tabular-nums">{deck.question_count}</td>
                  <td className="px-3 py-2 tabular-nums">{deck.sort_order}</td>
                  <td className="px-3 py-2">
                    <ActiveToggle deck={deck} />
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-1">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="text-muted-foreground"
                        aria-label="Edit"
                        onClick={() => {
                          setEditingDeck(deck);
                          setFormOpen(true);
                        }}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <DeleteButton deck={deck} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <DeckForm editingDeck={editingDeck} open={formOpen} onOpenChange={setFormOpen} />
    </div>
  );
}
