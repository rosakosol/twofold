"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { ArrowLeft, Pencil } from "lucide-react";
import { StatusPill } from "@/components/site/StatusPill";
import { gameGradient } from "@/components/admin/games/GameChip";
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
        <ArrowLeft className="h-4 w-4" aria-hidden /> Back to games
      </Link>

      {isLoading || !deck ? (
        <Skeleton className="mt-4 h-24 w-full rounded-lg" />
      ) : (
        <>
          {/* The deck in its game's gradient (docs/TWOFOLD_WEBSITE.md, section 9.2). */}
          <header className="deck-header mt-4" style={{ background: gameGradient(deck.game_type) }}>
            <div>
              <p className="deck-header-topic">{deck.topic}</p>
              <h1>
                {deck.emoji} {deck.title}
              </h1>
              <div className="deck-header-pills">
                <span className="pill">{deck.tier === "premium" ? "Premium" : "Plus"}</span>
                <span className="pill">{deck.question_count} questions</span>
                <StatusPill tone="surface" className="pill">
                  {deck.active ? "Active" : "Inactive"}
                </StatusPill>
              </div>
            </div>
            <button type="button" className="btn btn-white btn-sm" onClick={() => setFormOpen(true)}>
              <Pencil className="h-4 w-4" aria-hidden /> Edit deck
            </button>
          </header>

          <div className="mt-8">
            <ContentTable contentType={contentTypeForGameType(deck.game_type)} deckFilter={deck.id} />
          </div>

          <DeckForm editingDeck={deck} open={formOpen} onOpenChange={setFormOpen} />
        </>
      )}
    </div>
  );
}
