import type { Metadata } from "next";
import Link from "next/link";
import { Reveal } from "@/components/marketing/Reveal";
import { getFeatures } from "@/lib/marketing/sanity";
import { featureWithFallback, FEATURE_ICON, FEATURE_TONE } from "@/lib/marketing/featuresFallback";
import { FEATURE_SLUGS, APP_STORE_URL, type FeatureSlug } from "@/lib/marketing/config";

export const metadata: Metadata = {
  title: "Features",
  description:
    "Everything Twofold gives long-distance couples: a shared 3D relationship globe, live flight tracking, memories tied to real places, couple games, widgets, and a printable relationship record.",
};

function FeatureArt({ slug }: { slug: FeatureSlug }) {
  switch (slug) {
    case "relationship-globe":
      return (
        <div className="phone-mock">
          <div className="phone-mock-notch" />
          <div className="phone-mock-screen">
            <div className="mock-globe" aria-hidden>
              <div className="mock-dot" style={{ background: "var(--sky-blue)", top: "28%", left: "22%" }} />
              <div className="mock-dot" style={{ background: "var(--heart-red)", top: "62%", left: "68%" }} />
            </div>
          </div>
        </div>
      );
    case "live-flight-tracking":
      return (
        <div className="mock-card">
          <div className="mock-card-row">
            <strong style={{ fontFamily: "var(--font-display)", fontSize: 20 }}>MEL</strong>
            <span className="mock-dash" />
            <svg className="icon" style={{ width: 18, height: 18, color: "var(--sky-blue-deep)" }}>
              <use href="/assets/icons.svg#icon-plane" />
            </svg>
            <span className="mock-dash" />
            <strong style={{ fontFamily: "var(--font-display)", fontSize: 20 }}>SIN</strong>
          </div>
          <div className="mock-card-row" style={{ marginTop: 16 }}>
            <span className="icon-dot" style={{ background: "var(--leaf-green)" }}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-check" />
              </svg>
            </span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 14 }}>Landing in 2h 14m</div>
              <div style={{ fontSize: 12, color: "var(--subtle-ink)" }}>Dara · SQ 212 · On time</div>
            </div>
          </div>
        </div>
      );
    case "memories":
      return (
        <div className="mock-card">
          <div className="mock-card-row">
            <span className="icon-dot" style={{ background: "var(--heart-red)" }}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-pin" />
              </svg>
            </span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 14 }}>Gardens by the Bay</div>
              <div style={{ fontSize: 12, color: "var(--subtle-ink)" }}>Singapore · 3 memories</div>
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 8, marginTop: 14 }}>
            <div style={{ aspectRatio: "1", borderRadius: 10, background: "linear-gradient(135deg,var(--sky-blue-light),var(--sky-blue-deep))" }} />
            <div style={{ aspectRatio: "1", borderRadius: 10, background: "linear-gradient(135deg,#f6b6bd,var(--heart-red-deep))" }} />
            <div style={{ aspectRatio: "1", borderRadius: 10, background: "linear-gradient(135deg,#a8e0bc,var(--leaf-green-deep))" }} />
          </div>
        </div>
      );
    case "couple-games":
      return (
        <div className="mock-card">
          <div style={{ fontSize: 13, color: "var(--subtle-ink)", marginBottom: 10 }}>This or That</div>
          <div style={{ fontWeight: 700, fontSize: 16, marginBottom: 16 }}>Morning person or night owl?</div>
          <div style={{ display: "flex", gap: 10 }}>
            <div style={{ flex: 1, textAlign: "center", padding: 10, borderRadius: 12, background: "var(--card-bg-alt)", fontSize: 13, fontWeight: 600 }}>
              🌅 Morning
            </div>
            <div style={{ flex: 1, textAlign: "center", padding: 10, borderRadius: 12, background: "var(--card-bg-alt)", fontSize: 13, fontWeight: 600 }}>
              🌙 Night
            </div>
          </div>
        </div>
      );
    case "widgets-live-activities":
      return (
        <div className="phone-mock">
          <div className="phone-mock-notch" />
          <div className="phone-mock-screen" style={{ flexDirection: "column", gap: 14, padding: 20 }}>
            <div className="mock-card" style={{ maxWidth: 180, textAlign: "center" }}>
              <div style={{ fontSize: 12, color: "var(--subtle-ink)", marginBottom: 4 }}>Next reunion in</div>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 32 }}>12 days</div>
            </div>
            <div className="mock-card" style={{ maxWidth: 180 }}>
              <div className="mock-line" style={{ width: "70%", marginBottom: 8 }} />
              <div className="mock-line" style={{ width: "40%" }} />
            </div>
          </div>
        </div>
      );
    case "relationship-record":
      return (
        <div className="mock-card" style={{ maxWidth: 220 }}>
          <div className="mock-card-row">
            <span className="icon-dot" style={{ background: "var(--sky-blue)" }}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-file-download" />
              </svg>
            </span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 14 }}>Our Relationship Record</div>
              <div style={{ fontSize: 12, color: "var(--subtle-ink)" }}>48 pages · PDF</div>
            </div>
          </div>
          <div style={{ marginTop: 16, display: "flex", flexDirection: "column", gap: 8 }}>
            <div className="mock-line" style={{ width: "90%" }} />
            <div className="mock-line" style={{ width: "70%" }} />
            <div className="mock-line" style={{ width: "80%" }} />
          </div>
        </div>
      );
  }
}

export default async function FeaturesPage() {
  const docs = await getFeatures(FEATURE_SLUGS);

  return (
    <>
      <section className="page-hero">
        <p className="eyebrow">
          <svg className="icon">
            <use href="/assets/icons.svg#icon-sparkle" />
          </svg>
          Features
        </p>
        <h1>Everything your distance deserves</h1>
        <p>Twofold isn&apos;t just a flight tracker — it&apos;s a shared home for your relationship, wherever in the world you both are.</p>
      </section>

      <section>
        <div className="wrap">
          {FEATURE_SLUGS.map((slug, index) => {
            const feature = featureWithFallback(slug, docs[slug]);
            return (
              <Reveal key={slug} className={`feature-detail${index % 2 === 1 ? " reverse" : ""}`}>
                <div className="feature-detail-copy">
                  <div className={`feature-icon ${FEATURE_TONE[slug]}`}>
                    <svg className="icon">
                      <use href={`/assets/icons.svg#${FEATURE_ICON[slug]}`} />
                    </svg>
                  </div>
                  <h2>{feature.title}</h2>
                  <p>{feature.detailDescription}</p>
                  <ul className="feature-list">
                    {feature.bullets.map((bullet) => (
                      <li key={bullet}>
                        <svg className="icon">
                          <use href="/assets/icons.svg#icon-check" />
                        </svg>
                        <span>{bullet}</span>
                      </li>
                    ))}
                  </ul>
                </div>
                <div className="feature-detail-art">
                  <FeatureArt slug={slug} />
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>

      <section aria-labelledby="cta-heading">
        <div className="cta-banner reveal">
          <h2 id="cta-heading">Ready to start your globe?</h2>
          <p>Download Twofold free, then choose Plus or Premium for the full experience.</p>
          <div className="cta-row">
            <a className="btn btn-dark btn-lg" data-appstore-link href={APP_STORE_URL}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-apple" />
              </svg>
              Download for iOS
            </a>
            <Link className="btn btn-ghost btn-lg" href="/pricing" style={{ background: "rgba(255,255,255,0.9)" }}>
              See pricing
            </Link>
          </div>
        </div>
      </section>
    </>
  );
}
