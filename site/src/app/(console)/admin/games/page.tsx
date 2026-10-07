"use client";

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { GameTypeStats } from "@/components/admin/games/GameTypeStats";
import { OverallGameStats } from "@/components/admin/games/OverallGameStats";
import { DuplicateChecker } from "@/components/admin/games/DuplicateChecker";
import { CONTENT_TYPES, DECK_CONTENT_TYPES, type TieredContentTypeKey } from "@/lib/games/contentTypes";
import { ContentTable } from "@/components/admin/games/ContentTable";
import { ConsolePageHead } from "@/components/console/ConsoleUI";

const OVERALL_TAB = "overall";
const DUPLICATES_TAB = "duplicates";

export default function AdminGamesPage() {
  return (
    <div>
      <ConsolePageHead
        title="Games"
        description="Every game type at once under Overall. Pick a game type to manage its decks and entries."
      />

      <Tabs defaultValue={OVERALL_TAB}>
        <TabsList className="console-tabs">
          <TabsTrigger value={OVERALL_TAB}>Overall</TabsTrigger>
          <TabsTrigger value={DUPLICATES_TAB}>Similarity check</TabsTrigger>
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
