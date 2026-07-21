import Link from "next/link";
import { featureWithFallback, FEATURE_ICON, FEATURE_TONE } from "@/lib/marketing/featuresFallback";
import { FEATURE_SLUGS } from "@/lib/marketing/config";
import type { FeatureDoc } from "@/lib/marketing/sanity";
import { Reveal } from "@/components/marketing/Reveal";

export function FeatureTeaserGrid({ docs }: { docs: Record<string, FeatureDoc> }) {
  return (
    <>
      <div className="feature-grid">
        {FEATURE_SLUGS.map((slug) => {
          const feature = featureWithFallback(slug, docs[slug]);
          return (
            <Reveal key={slug} as="article" className="feature-card">
              <div className={`feature-icon ${FEATURE_TONE[slug]}`}>
                <svg className="icon">
                  <use href={`/assets/icons.svg#${FEATURE_ICON[slug]}`} />
                </svg>
              </div>
              <h3>{feature.title}</h3>
              <p>{feature.teaserDescription}</p>
            </Reveal>
          );
        })}
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
