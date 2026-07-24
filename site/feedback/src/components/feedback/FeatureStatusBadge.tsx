import { Badge } from "@/components/ui/badge";
import { STATUS_LABELS, type FeatureStatus } from "@/lib/utils/constants";
import { cn } from "@/lib/utils";

// Matches design_handoff_twofold_site/feedback.html's .status.* pills exactly —
// requested=grey, planned=purple, progress=blue, shipped=green.
const STATUS_STYLES: Record<FeatureStatus, string> = {
  requested: "bg-[rgba(134,149,163,0.16)] text-[#5b6b7a]",
  considering: "bg-[rgba(134,149,163,0.16)] text-[#5b6b7a]",
  planned: "bg-[rgba(120,110,220,0.14)] text-[#6b5fd0]",
  in_progress: "bg-[rgba(79,169,224,0.14)] text-[#3d8fc9]",
  released: "bg-[rgba(111,191,139,0.16)] text-[#4f9e6c]",
  closed: "bg-[rgba(134,149,163,0.16)] text-[#5b6b7a]",
};

export function FeatureStatusBadge({ status }: { status: FeatureStatus }) {
  return (
    <Badge
      variant="ghost"
      className={cn("shrink-0 rounded-full px-3 py-1 text-[0.75rem] font-semibold", STATUS_STYLES[status])}
    >
      {STATUS_LABELS[status]}
    </Badge>
  );
}
