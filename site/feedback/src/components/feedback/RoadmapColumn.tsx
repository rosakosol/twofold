import { CATEGORY_LABELS, type FeatureCategory } from "@/lib/utils/constants";
import type { RoadmapItem } from "@/lib/queries/useRoadmap";

export function RoadmapColumn({ label, items }: { label: string; items: RoadmapItem[] }) {
  return (
    <div>
      <div className="rm-col-head">
        <h3>{label}</h3>
        <span className="n">{items.length}</span>
      </div>

      <div className="rm-col">
        {items.length === 0 ? (
          <p className="rm-empty">Nothing here yet</p>
        ) : (
          items.map((item) => (
            <div key={item.id} className="rm-card">
              <p className="t">{item.title}</p>
              <div className="rm-card-foot">
                <span className="tag">#{CATEGORY_LABELS[item.category as FeatureCategory]}</span>
                <span className="fb-comments">
                  <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
                    <path d="M6 15l6-6 6 6" />
                  </svg>
                  {item.upvote_count}
                </span>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
