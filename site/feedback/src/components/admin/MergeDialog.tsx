"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Merge } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command";
import { useAdminFeatureList } from "@/lib/queries/useAdminFeatures";
import { useMergeFeatures } from "@/lib/queries/useAdminMutations";

export function MergeDialog({ featureId, title }: { featureId: string; title: string }) {
  const [open, setOpen] = useState(false);
  const { data: allFeatures } = useAdminFeatureList({});
  const mergeFeatures = useMergeFeatures();

  const candidates = (allFeatures ?? []).filter(
    (f) => f.id !== featureId && f.merged_into === null && f.status !== "closed"
  );

  async function handleSelect(targetId: string) {
    try {
      await mergeFeatures.mutateAsync({ sourceId: featureId, targetId });
      toast.success("Merged");
      setOpen(false);
    } catch {
      toast.error("Couldn't merge these requests.");
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <Button variant="ghost" size="icon-sm" className="text-muted-foreground">
            <Merge className="h-4 w-4" />
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Merge &ldquo;{title}&rdquo; into…</DialogTitle>
          <DialogDescription>
            Votes and comments move to the request you pick. This one closes and points to it.
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
                  value={feature.title}
                  onSelect={() => handleSelect(feature.id)}
                >
                  {feature.title}
                  <span className="ml-auto text-xs text-muted-foreground">
                    {feature.upvote_count} votes
                  </span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}
