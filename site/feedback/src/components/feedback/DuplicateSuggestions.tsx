import { ChevronUp } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { SimilarFeature } from "@/lib/queries/useDuplicateSearch";

interface DuplicateSuggestionsProps {
  items: SimilarFeature[];
  onConfirmNotDuplicate: () => void;
}

export function DuplicateSuggestions({ items, onConfirmNotDuplicate }: DuplicateSuggestionsProps) {
  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Did you mean one of these already-requested features?
      </p>
      <ul className="space-y-2">
        {items.map((item) => (
          <li
            key={item.id}
            className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm"
          >
            <span className="truncate">{item.title}</span>
            <span className="ml-2 flex shrink-0 items-center gap-1 text-xs text-muted-foreground">
              <ChevronUp className="h-3 w-3" />
              {item.upvote_count} votes
            </span>
          </li>
        ))}
      </ul>
      <Button type="button" variant="outline" size="sm" className="w-full" onClick={onConfirmNotDuplicate}>
        None of these — continue with my request
      </Button>
    </div>
  );
}
