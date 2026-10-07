import { CalendarCheck, Check, CircleDashed, Hammer, X } from "lucide-react";
import { StatusPill, type PillTone } from "@/components/site/StatusPill";
import { STATUS_LABELS, type FeatureStatus } from "@/lib/utils/constants";

/** Each status as the spec's pill (docs/TWOFOLD_WEBSITE.md, section 3): Requested is neutral,
 *  Planned the accent, In progress amber, Shipped green, each with an icon as well as the word. */
const STYLE: Record<FeatureStatus, { tone: PillTone; Icon: typeof Check }> = {
  requested: { tone: "neutral", Icon: CircleDashed },
  considering: { tone: "neutral", Icon: CircleDashed },
  planned: { tone: "accent", Icon: CalendarCheck },
  in_progress: { tone: "warning", Icon: Hammer },
  released: { tone: "success", Icon: Check },
  closed: { tone: "neutral", Icon: X },
};

export function FeatureStatusPill({ status }: { status: FeatureStatus }) {
  const { tone, Icon } = STYLE[status] ?? STYLE.requested;
  return (
    <StatusPill tone={tone} icon={<Icon />}>
      {STATUS_LABELS[status] ?? status}
    </StatusPill>
  );
}
