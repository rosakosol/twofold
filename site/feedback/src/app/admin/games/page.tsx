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
          Manage decks and the questions/prompts/topics that make up each game.
        </p>
      </div>

      <Tabs defaultValue="decks" className="mt-6">
        <TabsList>
          <TabsTrigger value="decks">Decks</TabsTrigger>
          {CONTENT_TYPES.map((c) => (
            <TabsTrigger key={c.key} value={c.key}>
              {c.label}
            </TabsTrigger>
          ))}
        </TabsList>

        <TabsContent value="decks" className="mt-4">
          <DeckTable />
        </TabsContent>
        {CONTENT_TYPES.map((c) => (
          <TabsContent key={c.key} value={c.key} className="mt-4">
            <ContentTable contentType={c} />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
