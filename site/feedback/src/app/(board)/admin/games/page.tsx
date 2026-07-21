"use client";

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { ContentTable } from "@/components/admin/games/ContentTable";
import { DeckTable } from "@/components/admin/games/DeckTable";
import { CONTENT_TYPES } from "@/lib/games/contentTypes";

export default function AdminGamesPage() {
  return (
    <div>
      <div>
        <h1 className="font-heading text-3xl font-bold tracking-tight">Games</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Each tab is a game type. Click into a deck to edit the questions that belong to it.
        </p>
      </div>

      <Tabs defaultValue={CONTENT_TYPES[0].key} className="mt-6">
        <TabsList>
          {CONTENT_TYPES.map((c) => (
            <TabsTrigger key={c.key} value={c.key}>
              {c.label}
            </TabsTrigger>
          ))}
        </TabsList>

        {CONTENT_TYPES.map((c) => (
          <TabsContent key={c.key} value={c.key} className="mt-4 flex flex-col gap-8">
            <div>
              <h2 className="mb-3 text-sm font-semibold text-muted-foreground">Decks</h2>
              <DeckTable gameType={c.gameType} />
            </div>
            <div>
              <h2 className="mb-3 text-sm font-semibold text-muted-foreground">All {c.label} entries</h2>
              <ContentTable contentType={c} />
            </div>
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
