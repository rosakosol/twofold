"use client";

import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { Pencil, Trash2, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StatusPill } from "@/components/site/StatusPill";
import { ConsoleEmpty } from "@/components/console/ConsoleUI";
import { GameChip } from "@/components/admin/games/GameChip";
import { useEmojiRenders } from "@/lib/games/emojiRenders";
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
          <Button variant="ghost" size="icon-sm" className="text-muted-foreground hover:text-destructive" aria-label={`Delete ${deck.title}`}>
            <Trash2 className="h-4 w-4" aria-hidden />
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
      aria-label={`${deck.title} is active`}
      checked={deck.active}
      disabled={update.isPending}
      onCheckedChange={(checked) =>
        update.mutate({ id: deck.id, patch: { active: checked } }, { onError: () => toast.error("Couldn't update.") })
      }
    />
  );
}

/** The deck's emoji and title, and a flag when this device draws the emoji as an empty box. */
function DeckName({ deck }: { deck: GameDeck }) {
  const renders = useEmojiRenders(deck.emoji);
  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      <GameChip gameType={deck.game_type} />
      <Link href={`/admin/games/decks/${deck.id}`} className="console-row-link">
        {deck.emoji} {deck.title}
      </Link>
      {renders === false && <StatusPill tone="warning">Icon not showing</StatusPill>}
    </span>
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
          <Plus className="h-4 w-4" aria-hidden /> New deck
        </Button>
      </div>

      {!decks || decks.length === 0 ? (
        <ConsoleEmpty title="No decks yet" />
      ) : (
        <div className="console-table-wrap">
          <table className="console-table">
            <thead>
              <tr>
                <th scope="col">Order</th>
                <th scope="col">Deck</th>
                <th scope="col">Category</th>
                {!gameType && <th scope="col">Game type</th>}
                <th scope="col">Tier</th>
                <th scope="col">Questions</th>
                <th scope="col">Active</th>
                <th scope="col">
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {decks.map((deck) => (
                <tr key={deck.id} className={deck.active ? undefined : "opacity-50"}>
                  <td className="num muted">{deck.sort_order}</td>
                  <td>
                    <DeckName deck={deck} />
                  </td>
                  <td className="muted">{deck.topic}</td>
                  {!gameType && <td>{LABEL_BY_GAME_TYPE.get(deck.game_type) ?? deck.game_type}</td>}
                  <td>
                    <StatusPill tone={deck.tier === "premium" ? "indigo" : "accent"}>
                      {deck.tier === "premium" ? "Premium" : "Plus"}
                    </StatusPill>
                  </td>
                  <td className="num">{deck.question_count}</td>
                  <td>
                    <ActiveToggle deck={deck} />
                  </td>
                  <td>
                    <div className="flex items-center justify-end gap-1">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="text-muted-foreground"
                        aria-label={`Edit ${deck.title}`}
                        onClick={() => {
                          setEditingDeck(deck);
                          setFormOpen(true);
                        }}
                      >
                        <Pencil className="h-4 w-4" aria-hidden />
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
