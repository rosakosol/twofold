"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetFooter } from "@/components/ui/sheet";
import { useCreateDeck, useUpdateDeck } from "@/lib/queries/useGameContentMutations";
import { CONTENT_TYPES, TIER_VALUES, type GameDeck, type GameType } from "@/lib/games/contentTypes";

interface Props {
  editingDeck: GameDeck | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function DeckForm({ editingDeck, open, onOpenChange }: Props) {
  const isEditing = editingDeck !== null;
  const create = useCreateDeck();
  const update = useUpdateDeck();

  const [title, setTitle] = useState("");
  const [topic, setTopic] = useState("");
  const [emoji, setEmoji] = useState("");
  const [gameType, setGameType] = useState<GameType>(CONTENT_TYPES[0].gameType);
  const [tier, setTier] = useState<(typeof TIER_VALUES)[number]>("plus");
  const [sortOrder, setSortOrder] = useState(0);
  const [active, setActive] = useState(true);

  useEffect(() => {
    if (!open) return;
    setTitle(editingDeck?.title ?? "");
    setTopic(editingDeck?.topic ?? "");
    setEmoji(editingDeck?.emoji ?? "");
    setGameType(editingDeck?.game_type ?? CONTENT_TYPES[0].gameType);
    setTier((editingDeck?.tier as (typeof TIER_VALUES)[number]) ?? "plus");
    setSortOrder(editingDeck?.sort_order ?? 0);
    setActive(editingDeck?.active ?? true);
  }, [open, editingDeck]);

  const canSave = title.trim().length > 0 && topic.trim().length > 0 && emoji.trim().length > 0;

  async function handleSave() {
    const patch = {
      title: title.trim(),
      topic: topic.trim(),
      emoji: emoji.trim(),
      game_type: gameType,
      tier,
      sort_order: sortOrder,
      active,
    };
    try {
      if (isEditing) {
        await update.mutateAsync({ id: editingDeck.id, patch });
        toast.success("Saved");
      } else {
        await create.mutateAsync(patch);
        toast.success("Created");
      }
      onOpenChange(false);
    } catch {
      toast.error("Couldn't save — check the fields and try again.");
    }
  }

  const isSaving = create.isPending || update.isPending;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="flex flex-col overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{isEditing ? "Edit deck" : "New deck"}</SheetTitle>
          <SheetDescription>
            {isEditing
              ? "Question count is maintained automatically — it isn't editable here."
              : "Groups questions of one game type under a title players browse."}
          </SheetDescription>
        </SheetHeader>

        <div className="flex flex-col gap-4 px-4">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="deck-title">Title</Label>
            <Input id="deck-title" value={title} onChange={(e) => setTitle(e.target.value)} />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="deck-topic">Topic</Label>
            <Input id="deck-topic" value={topic} onChange={(e) => setTopic(e.target.value)} />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="deck-emoji">Emoji</Label>
            <Input id="deck-emoji" value={emoji} onChange={(e) => setEmoji(e.target.value)} className="w-16" />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label>Game type</Label>
            <Select
              value={gameType}
              onValueChange={(v) => v && setGameType(v as GameType)}
              disabled={isEditing}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {CONTENT_TYPES.map((c) => (
                  <SelectItem key={c.gameType} value={c.gameType}>
                    {c.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {isEditing && (
              <p className="text-xs text-muted-foreground">
                Can&apos;t change game type once questions may already be assigned to this deck.
              </p>
            )}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label>Tier</Label>
            <Select value={tier} onValueChange={(v) => v && setTier(v as (typeof TIER_VALUES)[number])}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TIER_VALUES.map((t) => (
                  <SelectItem key={t} value={t}>
                    {t}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="deck-sort">Sort order</Label>
            <Input
              id="deck-sort"
              type="number"
              value={sortOrder}
              onChange={(e) => setSortOrder(Number(e.target.value) || 0)}
            />
          </div>

          {isEditing && (
            <div className="flex flex-col gap-1.5">
              <Label>Question count</Label>
              <p className="text-sm text-muted-foreground">{editingDeck.question_count} (auto-maintained)</p>
            </div>
          )}

          <div className="flex items-center justify-between">
            <Label htmlFor="deck-active">Active</Label>
            <Switch id="deck-active" checked={active} onCheckedChange={setActive} />
          </div>
        </div>

        <SheetFooter>
          <Button onClick={handleSave} disabled={!canSave || isSaving}>
            {isSaving ? "Saving…" : "Save"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
