import { CATEGORY_LABELS, type FeatureCategory } from "@/lib/utils/constants";

/** A request's category as a chip, as on the public board. */
export function CategoryBadge({ category }: { category: FeatureCategory }) {
  return <span className="pill pill-raised">{CATEGORY_LABELS[category] ?? category}</span>;
}
