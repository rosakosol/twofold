import Link from "next/link";
import { EmptyState } from "@/components/feedback/EmptyState";
import { SearchX } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function NotFound() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-16">
      <EmptyState
        icon={SearchX}
        title="Request not found"
        description="It may have been removed, merged into another request, or the link is wrong."
        action={
          <Button size="sm" render={<Link href="/">Back to feedback</Link>} />
        }
      />
    </div>
  );
}
