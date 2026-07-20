"use client";

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  CATEGORY_LABELS,
  CATEGORY_VALUES,
  SORT_LABELS,
  STATUS_LABELS,
  STATUS_VALUES,
  type FeatureCategory,
  type FeatureStatus,
  type SortOption,
} from "@/lib/utils/constants";

interface FiltersProps {
  category: FeatureCategory | undefined;
  status: FeatureStatus | undefined;
  sort: SortOption;
  onCategoryChange: (value: FeatureCategory | undefined) => void;
  onStatusChange: (value: FeatureStatus | undefined) => void;
  onSortChange: (value: SortOption) => void;
}

const ALL = "__all__";

export function Filters({
  category,
  status,
  sort,
  onCategoryChange,
  onStatusChange,
  onSortChange,
}: FiltersProps) {
  return (
    <div className="flex flex-wrap gap-2">
      <Select
        value={category ?? ALL}
        onValueChange={(value) => onCategoryChange(value === ALL ? undefined : (value as FeatureCategory))}
      >
        <SelectTrigger size="sm">
          <SelectValue placeholder="Category" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL}>All categories</SelectItem>
          {CATEGORY_VALUES.map((value) => (
            <SelectItem key={value} value={value}>
              {CATEGORY_LABELS[value]}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select
        value={status ?? ALL}
        onValueChange={(value) => onStatusChange(value === ALL ? undefined : (value as FeatureStatus))}
      >
        <SelectTrigger size="sm">
          <SelectValue placeholder="Status" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL}>All statuses</SelectItem>
          {STATUS_VALUES.map((value) => (
            <SelectItem key={value} value={value}>
              {STATUS_LABELS[value]}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select value={sort} onValueChange={(value) => onSortChange(value as SortOption)}>
        <SelectTrigger size="sm">
          <SelectValue placeholder="Sort" />
        </SelectTrigger>
        <SelectContent>
          {(Object.keys(SORT_LABELS) as SortOption[]).map((value) => (
            <SelectItem key={value} value={value}>
              {SORT_LABELS[value]}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
