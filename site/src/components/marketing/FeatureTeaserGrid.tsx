import Link from "next/link";
import type { ResolvedFeature } from "@/lib/marketing/featuresFallback";
import { Reveal } from "@/components/marketing/Reveal";

export function FeatureTeaserGrid({ features }: { features: ResolvedFeature[] }) {
  return (
    <>
      <div className="feature-grid">
        {features.map((feature) => (
          <Reveal key={feature.slug} as="article" className="feature-card">
            <div className={`feature-icon ${feature.tone}`}>
              <svg className="icon">
                <use href={`/assets/icons.svg#${feature.icon}`} />
              </svg>
            </div>
            <h3>{feature.title}</h3>
            <p>{feature.teaserDescription}</p>
          </Reveal>
        ))}
      </div>
      <p style={{ textAlign: "center", marginTop: 36 }}>
        <Link className="text-link" href="/features">
          See every feature
          <svg className="icon">
            <use href="/assets/icons.svg#icon-arrow-right" />
          </svg>
        </Link>
      </p>
    </>
  );
}
