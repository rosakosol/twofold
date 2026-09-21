"use client";

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { GameTypeStats } from "@/components/admin/games/GameTypeStats";
import { OverallGameStats } from "@/components/admin/games/OverallGameStats";
import { DuplicateChecker } from "@/components/admin/games/DuplicateChecker";
import { CONTENT_TYPES, DECK_CONTENT_TYPES, type TieredContentTypeKey } from "@/lib/games/contentTypes";
import { ContentTable } from "@/components/admin/games/ContentTable";

const OVERALL_TAB = "overall";
const DUPLICATES_TAB = "duplicates";

export default function AdminGamesPage() {
  return (
    <div>
      <div>
        <h1 className="font-heading text-xl font-semibold tracking-tight">Games</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Overall covers every game type at once — pick a game type&apos;s own tab to manage its Decks or Entries.
        </p>
      </div>

      <Tabs defaultValue={OVERALL_TAB} className="mt-6">
        <TabsList>
          <TabsTrigger value={OVERALL_TAB}>Overall</TabsTrigger>
          <TabsTrigger value={DUPLICATES_TAB}>Similarity Check</TabsTrigger>
          {CONTENT_TYPES.map((c) => (
            <TabsTrigger key={c.key} value={c.key}>
              {c.label}
            </TabsTrigger>
          ))}
        </TabsList>

        <TabsContent value={OVERALL_TAB} className="mt-4">
          <OverallGameStats />
        </TabsContent>
        <TabsContent value={DUPLICATES_TAB} className="mt-4">
          <DuplicateChecker />
        </TabsContent>
        {/* Deck-backed types get the stats card; the daily question bank has no decks and no tier
            split to chart, so it goes straight to its content table. */}
        {DECK_CONTENT_TYPES.map((c) => (
          <TabsContent key={c.key} value={c.key} className="mt-4">
            <GameTypeStats contentType={{ ...c, key: c.key as TieredContentTypeKey }} />
          </TabsContent>
        ))}
        {CONTENT_TYPES.filter((c) => c.gameType === null).map((c) => (
          <TabsContent key={c.key} value={c.key} className="mt-4">
            <ContentTable contentType={c} />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
