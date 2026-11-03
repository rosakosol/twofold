"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Loader2, Merge } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command";
import { useAdminFeatureList } from "@/lib/queries/useAdminFeatures";
import { describeDbError } from "@/lib/supabase/dbError";
import { useMergeFeatures } from "@/lib/queries/useAdminMutations";

/**
 * Merge one request into another. Two steps, because the merge can't be undone from here: picking
 * a target only selects it, and a separate button carries it out.
 *
 * It used to merge on `onSelect`, so a stray Enter in the list merged whichever row was
 * highlighted, and two quick picks could fire two merges. Items were keyed by title, which cmdk
 * uses as the identity, so two requests with the same title collided.
 */
export function MergeDialog({ featureId, title }: { featureId: string; title: string }) {
  const [open, setOpen] = useState(false);
  const [targetId, setTargetId] = useState<string | null>(null);
  // Only while open, and under the same key as the page's tiles, so it reuses their full read
  // rather than making another one for every row on every page load.
  const { data: allFeatures } = useAdminFeatureList({ sort: "newest" }, { enabled: open });
  const mergeFeatures = useMergeFeatures();
  const busy = mergeFeatures.isPending;

  const candidates = (allFeatures ?? []).filter(
    (f) => f.id !== featureId && f.merged_into === null && f.status !== "closed"
  );
  const target = candidates.find((f) => f.id === targetId) ?? null;

  function handleOpenChange(next: boolean) {
    if (busy) return;
    setOpen(next);
    if (!next) setTargetId(null);
  }

  async function handleMerge() {
    if (!target || busy) return;
    try {
      await mergeFeatures.mutateAsync({ sourceId: featureId, targetId: target.id });
      toast.success(`Merged into “${target.title}”`);
      // Not handleOpenChange: `busy` in this closure is still the value from before the merge.
      setOpen(false);
      setTargetId(null);
    } catch (error) {
      toast.error(describeDbError(error, "Couldn't merge these requests."));
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            className="text-muted-foreground"
            aria-label={`Merge “${title}” into another request`}
          >
            <Merge className="h-4 w-4" />
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Merge &ldquo;{title}&rdquo; into…</DialogTitle>
          <DialogDescription>
            Votes move to the request you pick. This one closes and points to it.
          </DialogDescription>
        </DialogHeader>
        <Command className="rounded-lg border">
          <CommandInput placeholder="Search requests…" />
          <CommandList>
            <CommandEmpty>No matching requests.</CommandEmpty>
            <CommandGroup>
              {candidates.map((feature) => (
                <CommandItem
                  key={feature.id}
                  value={feature.id}
                  keywords={[feature.title]}
                  disabled={busy}
                  onSelect={() => setTargetId(feature.id)}
                >
                  {feature.title}
                  <span className="ml-auto text-xs text-muted-foreground">
                    {feature.id === targetId ? "Selected · " : ""}
                    {feature.upvote_count} votes
                  </span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={handleMerge} disabled={!target || busy}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            {target ? `Merge into “${target.title}”` : "Pick a request to merge into"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
