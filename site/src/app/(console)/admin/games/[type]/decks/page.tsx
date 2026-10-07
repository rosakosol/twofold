"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { DeckTable } from "@/components/admin/games/DeckTable";
import { contentTypeFor, type ContentTypeKey } from "@/lib/games/contentTypes";
import { ConsolePageHead } from "@/components/console/ConsoleUI";

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
        <ArrowLeft className="h-4 w-4" aria-hidden /> Back to games
      </Link>

      {!contentType ? (
        <p className="mt-4 text-sm text-muted-foreground">Unknown game type.</p>
      ) : (
        <>
          <div className="mt-4">
            <ConsolePageHead title={`${contentType.label} decks`} description="Turn decks on and off, edit them, and open one to see its questions." />
          </div>
          <div>
            <DeckTable gameType={contentType.gameType ?? undefined} />
          </div>
        </>
      )}
    </div>
  );
}
