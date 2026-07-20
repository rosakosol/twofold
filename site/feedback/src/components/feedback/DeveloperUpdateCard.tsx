import { Megaphone } from "lucide-react";
import type { DeveloperUpdate } from "@/lib/queries/useDeveloperUpdates";
import { formatRelativeTime } from "@/lib/utils/format";

export function DeveloperUpdateCard({ update }: { update: DeveloperUpdate }) {
  return (
    <div className="rounded-lg border bg-primary/5 p-4">
      <div className="flex items-center gap-2 text-sm font-medium text-primary">
        <Megaphone className="h-4 w-4" />
        Update from the team
        <span className="ml-auto text-xs font-normal text-muted-foreground">
          {formatRelativeTime(update.created_at)}
        </span>
      </div>
      <p className="mt-2 text-sm whitespace-pre-wrap">{update.body}</p>
    </div>
  );
}
