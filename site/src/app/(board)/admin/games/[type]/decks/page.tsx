"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { DeckTable } from "@/components/admin/games/DeckTable";
import { contentTypeFor, type ContentTypeKey } from "@/lib/games/contentTypes";

export default function GameTypeDecksPage() {
  const { type } = useParams<{ type: string }>();
  const contentType = (() => {
    try {
      return contentTypeFor(type as ContentTypeKey);
    } catch {
      return null;
    }
  })();

  return (
    <div>
      <Link
        href="/admin/games"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Back to Games
      </Link>

      {!contentType ? (
        <p className="mt-4 text-sm text-muted-foreground">Unknown game type.</p>
      ) : (
        <>
          <h1 className="mt-4 font-heading text-xl font-semibold tracking-tight">{contentType.label} Decks</h1>
          <div className="mt-6">
            <DeckTable gameType={contentType.gameType} />
          </div>
        </>
      )}
    </div>
  );
}
