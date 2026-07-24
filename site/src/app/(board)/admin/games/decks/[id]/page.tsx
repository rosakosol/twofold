"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { ArrowLeft, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { useGameDeck } from "@/lib/queries/useGameContent";
import { DeckForm } from "@/components/admin/games/DeckForm";
import { ContentTable } from "@/components/admin/games/ContentTable";
import { contentTypeForGameType } from "@/lib/games/contentTypes";

export default function DeckDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { data: deck, isLoading } = useGameDeck(id);
  const [formOpen, setFormOpen] = useState(false);

  return (
    <div>
      <Link
        href="/admin/games"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Back to Games
      </Link>

      {isLoading || !deck ? (
        <Skeleton className="mt-4 h-24 w-full rounded-lg" />
      ) : (
        <>
          <div className="mt-4 flex items-start justify-between">
            <div>
              <h1 className="font-heading text-xl font-semibold tracking-tight">
                {deck.emoji} {deck.title}
              </h1>
              <p className="mt-1 text-sm text-muted-foreground">{deck.topic}</p>
              <div className="mt-2 flex items-center gap-2">
                <Badge variant={deck.tier === "premium" ? "default" : "secondary"}>{deck.tier}</Badge>
                {!deck.active && <Badge variant="secondary">Inactive</Badge>}
                <span className="text-xs text-muted-foreground">{deck.question_count} questions</span>
              </div>
            </div>
            <Button variant="outline" size="sm" onClick={() => setFormOpen(true)}>
              <Pencil className="h-4 w-4" /> Edit deck
            </Button>
          </div>

          <div className="mt-8">
            <ContentTable contentType={contentTypeForGameType(deck.game_type)} deckFilter={deck.id} />
          </div>

          <DeckForm editingDeck={deck} open={formOpen} onOpenChange={setFormOpen} />
        </>
      )}
    </div>
  );
}
