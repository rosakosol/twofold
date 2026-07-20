"use client";

import { toast } from "sonner";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useUpdateFeatureStatus } from "@/lib/queries/useAdminMutations";
import { STATUS_LABELS, STATUS_VALUES, type FeatureStatus } from "@/lib/utils/constants";

export function StatusSelect({ featureId, status }: { featureId: string; status: FeatureStatus }) {
  const updateStatus = useUpdateFeatureStatus();

  function handleChange(value: string | null) {
    if (!value) return;
    updateStatus.mutate(
      { id: featureId, status: value as FeatureStatus },
      { onError: () => toast.error("Couldn't update status.") }
    );
  }

  return (
    <Select value={status} onValueChange={handleChange} disabled={updateStatus.isPending}>
      <SelectTrigger size="sm">
        <SelectValue />
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
