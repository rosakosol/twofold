"use client";

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { GameTypeStats } from "@/components/admin/games/GameTypeStats";
import { CONTENT_TYPES } from "@/lib/games/contentTypes";

export default function AdminGamesPage() {
  return (
    <div>
      <div>
        <h1 className="font-heading text-xl font-semibold tracking-tight">Games</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Each tab is a game type. Pick Decks or Entries to manage that content.
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
          <TabsContent key={c.key} value={c.key} className="mt-4">
            <GameTypeStats contentType={c} />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
