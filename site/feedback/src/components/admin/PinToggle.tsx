"use client";

import { toast } from "sonner";
import { Pin, PinOff } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useTogglePin } from "@/lib/queries/useAdminMutations";

export function PinToggle({ featureId, isPinned }: { featureId: string; isPinned: boolean }) {
  const togglePin = useTogglePin();

  return (
    <Button
      variant="ghost"
      size="icon-sm"
      disabled={togglePin.isPending}
      onClick={() =>
        togglePin.mutate({ id: featureId, isPinned }, { onError: () => toast.error("Couldn't update pin.") })
      }
      aria-label={isPinned ? "Unpin" : "Pin"}
      className={isPinned ? "text-primary" : "text-muted-foreground"}
    >
      {isPinned ? <PinOff className="h-4 w-4" /> : <Pin className="h-4 w-4" />}
    </Button>
  );
}
