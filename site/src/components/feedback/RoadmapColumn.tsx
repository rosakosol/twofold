import { ChevronUp } from "lucide-react";
import { CATEGORY_LABELS, type FeatureCategory } from "@/lib/utils/constants";
import type { RoadmapItem } from "@/lib/queries/useRoadmap";

/** One stage of the roadmap: its name and count, then a compact card per request. */
export function RoadmapColumn({ label, items }: { label: string; items: RoadmapItem[] }) {
  const id = `rm-${label.toLowerCase().replace(/[^a-z]+/g, "-")}`;
  return (
    <section className="rm-col-wrap" aria-labelledby={id}>
      <div className="rm-col-head">
        <h3 id={id}>{label}</h3>
        <span className="rm-count" aria-label={`${items.length} ${items.length === 1 ? "request" : "requests"}`}>
          {items.length}
        </span>
      </div>

      <div className="rm-col">
        {items.length === 0 ? (
          <p className="rm-empty">Nothing here yet</p>
        ) : (
          <ul>
            {items.map((item) => (
              <li key={item.id} className="rm-card">
                <p className="rm-card-title">{item.title}</p>
                <div className="rm-card-foot">
                  <span className="pill pill-raised">{CATEGORY_LABELS[item.category as FeatureCategory]}</span>
                  <span className="rm-votes" aria-label={`${item.upvote_count} ${item.upvote_count === 1 ? "vote" : "votes"}`}>
                    <ChevronUp aria-hidden />
                    {item.upvote_count}
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
