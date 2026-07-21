"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
  SheetFooter,
} from "@/components/ui/sheet";
import { useCreateContent, useUpdateContent } from "@/lib/queries/useGameContentMutations";
import { DIFFICULTY_VALUES, TIER_VALUES, type ContentRow, type ContentTypeConfig, type GameDeck, type TriviaQuestion } from "@/lib/games/contentTypes";

const NO_DECK = "__no_deck__";

interface Props {
  contentType: ContentTypeConfig;
  decks: GameDeck[];
  editingRow: ContentRow | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Pre-selected deck for new entries — used when creating from within a deck's detail view. */
  defaultDeckId?: string;
}

function optionsOf(row: ContentRow | null): string[] {
  if (!row || !("options" in row)) return ["", ""];
  const raw = (row as TriviaQuestion).options;
  if (Array.isArray(raw) && raw.every((o) => typeof o === "string")) return raw as string[];
  return ["", ""];
}

export function ContentForm({ contentType, decks, editingRow, open, onOpenChange, defaultDeckId }: Props) {
  const isEditing = editingRow !== null;
  const create = useCreateContent(contentType.key);
  const update = useUpdateContent(contentType.key);

  const [textValues, setTextValues] = useState<Record<string, string>>({});
  const [category, setCategory] = useState("");
  const [tier, setTier] = useState<(typeof TIER_VALUES)[number]>("plus");
  const [deckId, setDeckId] = useState<string>(NO_DECK);
  const [active, setActive] = useState(true);

  // Trivia-only state
  const [options, setOptions] = useState<string[]>(["", ""]);
  const [correctAnswer, setCorrectAnswer] = useState("");
  const [explanation, setExplanation] = useState("");
  const [difficulty, setDifficulty] = useState<string>("");

  // Re-seed every field whenever the sheet opens for a (possibly different) row —
  // resetting only on `open` would leave stale values if the user opens straight from
  // one row's edit sheet into another's via the table, so this keys off `editingRow` too.
  useEffect(() => {
    if (!open) return;
    const seeded: Record<string, string> = {};
    for (const field of contentType.textFields) {
      seeded[field.key] = editingRow ? String((editingRow as unknown as Record<string, unknown>)[field.key] ?? "") : "";
    }
    setTextValues(seeded);
    setCategory(editingRow?.category ?? "");
    setTier((editingRow?.tier as (typeof TIER_VALUES)[number]) ?? "plus");
    setDeckId(editingRow?.deck_id ?? defaultDeckId ?? NO_DECK);
    setActive(editingRow?.active ?? true);

    if (contentType.isTrivia) {
      const trivia = editingRow as TriviaQuestion | null;
      setOptions(optionsOf(editingRow));
      setCorrectAnswer(trivia?.correct_answer ?? "");
      setExplanation(trivia?.explanation ?? "");
      setDifficulty(trivia?.difficulty ?? "");
    }
  }, [open, editingRow, contentType, defaultDeckId]);

  const nonEmptyOptions = options.map((o) => o.trim()).filter(Boolean);

  function canSave(): boolean {
    if (!category.trim()) return false;
    if (contentType.textFields.some((f) => !textValues[f.key]?.trim())) return false;
    if (contentType.isTrivia) {
      if (nonEmptyOptions.length < 2) return false;
      if (!nonEmptyOptions.includes(correctAnswer)) return false;
    }
    return true;
  }

  async function handleSave() {
    const patch: Record<string, unknown> = {
      category: category.trim(),
      tier,
      deck_id: deckId === NO_DECK ? null : deckId,
      active,
      ...Object.fromEntries(contentType.textFields.map((f) => [f.key, textValues[f.key]?.trim() ?? ""])),
    };
    if (contentType.isTrivia) {
      patch.options = nonEmptyOptions;
      patch.correct_answer = correctAnswer;
      patch.explanation = explanation.trim() || null;
      patch.difficulty = difficulty || null;
    }

    try {
      if (isEditing) {
        await update.mutateAsync({ id: editingRow.id, patch: patch as never });
        toast.success("Saved");
      } else {
        await create.mutateAsync(patch as never);
        toast.success("Created");
      }
      onOpenChange(false);
    } catch {
      toast.error("Couldn't save — check the fields and try again.");
    }
  }

  const isSaving = create.isPending || update.isPending;
  const relevantDecks = decks.filter((d) => d.game_type === contentType.gameType);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="flex flex-col overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{isEditing ? `Edit ${contentType.label}` : `New ${contentType.label}`}</SheetTitle>
          <SheetDescription>
            {isEditing ? "Update this entry." : `Add a new ${contentType.label.toLowerCase()} entry.`}
          </SheetDescription>
        </SheetHeader>

        <div className="flex flex-col gap-4 px-4">
          {contentType.textFields.map((field) => (
            <div key={field.key} className="flex flex-col gap-1.5">
              <Label htmlFor={field.key}>{field.label}</Label>
              {field.multiline ? (
                <Textarea
                  id={field.key}
                  value={textValues[field.key] ?? ""}
                  onChange={(e) => setTextValues((prev) => ({ ...prev, [field.key]: e.target.value }))}
                  rows={3}
                />
              ) : (
                <Input
                  id={field.key}
                  value={textValues[field.key] ?? ""}
                  onChange={(e) => setTextValues((prev) => ({ ...prev, [field.key]: e.target.value }))}
                />
              )}
            </div>
          ))}

          {contentType.isTrivia && (
            <>
              <div className="flex flex-col gap-1.5">
                <Label>Options</Label>
                <div className="flex flex-col gap-2">
                  {options.map((opt, index) => (
                    <div key={index} className="flex items-center gap-2">
                      <Input
                        value={opt}
                        placeholder={`Option ${index + 1}`}
                        onChange={(e) => {
                          const next = [...options];
                          next[index] = e.target.value;
                          setOptions(next);
                          // Keep correct_answer in sync if it was pointing at this option's old text.
                          if (correctAnswer === opt) setCorrectAnswer(e.target.value);
                        }}
                      />
                      {options.length > 2 && (
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon-sm"
                          onClick={() => {
                            const removed = options[index];
                            setOptions(options.filter((_, i) => i !== index));
                            if (correctAnswer === removed) setCorrectAnswer("");
                          }}
                        >
                          <X className="h-4 w-4" />
                        </Button>
                      )}
                    </div>
                  ))}
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="w-fit"
                    onClick={() => setOptions([...options, ""])}
                  >
                    <Plus className="h-4 w-4" /> Add option
                  </Button>
                </div>
              </div>

              <div className="flex flex-col gap-1.5">
                <Label>Correct answer</Label>
                <Select value={correctAnswer || undefined} onValueChange={(v) => v && setCorrectAnswer(v)}>
                  <SelectTrigger>
                    <SelectValue placeholder={nonEmptyOptions.length ? "Choose the correct option" : "Fill in options first"} />
                  </SelectTrigger>
                  <SelectContent>
                    {nonEmptyOptions.map((opt) => (
                      <SelectItem key={opt} value={opt}>
                        {opt}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="flex flex-col gap-1.5">
                <Label htmlFor="explanation">Explanation (optional)</Label>
                <Textarea id="explanation" value={explanation} onChange={(e) => setExplanation(e.target.value)} rows={2} />
              </div>

              <div className="flex flex-col gap-1.5">
                <Label>Difficulty (optional)</Label>
                <Select value={difficulty || undefined} onValueChange={(v) => setDifficulty(v ?? "")}>
                  <SelectTrigger>
                    <SelectValue placeholder="Unset" />
                  </SelectTrigger>
                  <SelectContent>
                    {DIFFICULTY_VALUES.map((d) => (
                      <SelectItem key={d} value={d}>
                        {d}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </>
          )}

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="category">Category</Label>
            <Input id="category" value={category} onChange={(e) => setCategory(e.target.value)} />
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
            <Label>Deck (optional)</Label>
            <Select value={deckId} onValueChange={(v) => v && setDeckId(v)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_DECK}>No deck</SelectItem>
                {relevantDecks.map((deck) => (
                  <SelectItem key={deck.id} value={deck.id}>
                    {deck.emoji} {deck.title}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex items-center justify-between">
            <Label htmlFor="active">Active</Label>
            <Switch id="active" checked={active} onCheckedChange={setActive} />
          </div>
        </div>

        <SheetFooter>
          <Button onClick={handleSave} disabled={!canSave() || isSaving}>
            {isSaving ? "Saving…" : "Save"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
