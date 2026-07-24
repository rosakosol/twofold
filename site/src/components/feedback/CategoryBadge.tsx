import { Badge } from "@/components/ui/badge";
import { CATEGORY_LABELS, type FeatureCategory } from "@/lib/utils/constants";

export function CategoryBadge({ category }: { category: FeatureCategory }) {
  return <Badge variant="outline">{CATEGORY_LABELS[category]}</Badge>;
}
