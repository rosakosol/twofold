import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { ROADMAP_STATUSES, STATUS_LABELS, type FeatureStatus } from "@/lib/utils/constants";

export function StatusTimeline({ status }: { status: FeatureStatus }) {
  if (status === "closed") {
    return (
      <p className="text-sm text-muted-foreground">
        This request is <span className="font-medium text-foreground">closed</span>.
      </p>
    );
  }

  const currentIndex = ROADMAP_STATUSES.indexOf(status);

  return (
    <ol className="flex items-center">
      {ROADMAP_STATUSES.map((step, index) => {
        const isDone = index < currentIndex;
        const isCurrent = index === currentIndex;

        return (
          <li key={step} className="flex flex-1 items-center last:flex-none">
            <div className="flex flex-col items-center gap-1.5">
              <div
                className={cn(
                  "flex h-6 w-6 items-center justify-center rounded-full border text-xs font-medium",
                  isDone && "border-primary bg-primary text-primary-foreground",
                  isCurrent && "border-primary text-primary",
                  !isDone && !isCurrent && "border-border text-muted-foreground"
                )}
              >
                {isDone ? <Check className="h-3 w-3" /> : index + 1}
              </div>
              <span
                className={cn(
                  "text-[11px] whitespace-nowrap",
                  isCurrent ? "font-medium text-foreground" : "text-muted-foreground"
                )}
              >
                {STATUS_LABELS[step]}
              </span>
            </div>
            {index < ROADMAP_STATUSES.length - 1 && (
              <div className={cn("mx-1 h-px flex-1", isDone ? "bg-primary" : "bg-border")} />
            )}
          </li>
        );
      })}
    </ol>
  );
}
