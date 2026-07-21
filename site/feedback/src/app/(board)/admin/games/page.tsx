"use client";

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { GameTypeStats } from "@/components/admin/games/GameTypeStats";
import { OverallGameStats } from "@/components/admin/games/OverallGameStats";
import { CONTENT_TYPES } from "@/lib/games/contentTypes";

const OVERALL_TAB = "overall";

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
          {CONTENT_TYPES.map((c) => (
            <TabsTrigger key={c.key} value={c.key}>
              {c.label}
            </TabsTrigger>
          ))}
        </TabsList>

        <TabsContent value={OVERALL_TAB} className="mt-4">
          <OverallGameStats />
        </TabsContent>
        {CONTENT_TYPES.map((c) => (
          <TabsContent key={c.key} value={c.key} className="mt-4">
            <GameTypeStats contentType={c} />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
