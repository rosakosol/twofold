import { Badge } from "@/components/ui/badge";
import { STATUS_LABELS, type FeatureStatus } from "@/lib/utils/constants";
import { cn } from "@/lib/utils";

const STATUS_STYLES: Record<FeatureStatus, string> = {
  requested: "bg-muted text-muted-foreground",
  considering: "bg-sky-500/10 text-sky-600 dark:text-sky-400",
  planned: "bg-indigo-500/10 text-indigo-600 dark:text-indigo-400",
  in_progress: "bg-amber-500/10 text-amber-600 dark:text-amber-400",
  released: "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
  closed: "bg-zinc-500/10 text-zinc-500",
};

export function FeatureStatusBadge({ status }: { status: FeatureStatus }) {
  return (
    <Badge variant="ghost" className={cn(STATUS_STYLES[status])}>
      {STATUS_LABELS[status]}
    </Badge>
  );
}
