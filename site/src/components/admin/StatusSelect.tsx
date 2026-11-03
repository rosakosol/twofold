"use client";

import { toast } from "sonner";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useUpdateFeatureStatus } from "@/lib/queries/useAdminMutations";
import { describeDbError } from "@/lib/supabase/dbError";
import { STATUS_LABELS, STATUS_VALUES, type FeatureStatus } from "@/lib/utils/constants";

export function StatusSelect({ featureId, status, title }: { featureId: string; status: FeatureStatus; title?: string }) {
  const updateStatus = useUpdateFeatureStatus();

  function handleChange(value: string | null) {
    if (!value) return;
    updateStatus.mutate(
      { id: featureId, status: value as FeatureStatus },
      { onError: (error) => toast.error(describeDbError(error, "Couldn't update status.")) }
    );
  }

  return (
    <Select value={status} onValueChange={handleChange} disabled={updateStatus.isPending}>
      <SelectTrigger size="sm" aria-label={title ? `Status of “${title}”` : "Status"}>
        <SelectValue labels={STATUS_LABELS} />
      </SelectTrigger>
      <SelectContent>
        {STATUS_VALUES.map((value) => (
          <SelectItem key={value} value={value}>
            {STATUS_LABELS[value]}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
