import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { Reveal } from "@/components/marketing/Reveal";
import { getFeatures } from "@/lib/marketing/sanity";
import { resolveFeatures, type ResolvedFeature } from "@/lib/marketing/featuresFallback";
import { PHONE_SHOT_HEIGHT as SHOT_HEIGHT } from "@/lib/marketing/phoneScreens";

export const metadata: Metadata = {
  title: "Features",
  description:
    "Everything Twofold gives long-distance couples: memories tied to real places, every trip on one shared timeline, live flight tracking, couple games, widgets, and an exportable record of your relationship.",
};

// Real app screenshots, keyed by feature slug. A slug listed here renders the screenshot on its
// own (see `.feature-shot`); anything not listed falls back to the hand-built CSS mockup below,
// which is why the two can coexist while the rest of the screenshots are captured.
//
// `src` must match the file on disk exactly, case included: these resolve on a case-insensitive
// dev filesystem but 404 on Vercel's Linux builders, so a wrong case looks fine locally and
// ships a blank space.
const FEATURE_SHOTS: Record<string, { src: string; alt: string; width: number }> = {
  "live-flight-tracking": {
    src: "/assets/phone-screen/Flight-Tracking.png",
    alt: "Live flight tracking in Twofold, showing a partner's flight status and arrival time",
    width: 1019,
  },
  memories: {
    src: "/assets/phone-screen/Memory-Detail.png",
    alt: "A saved memory in Twofold, with a photo and note attached to the place it happened",
    width: 1019,
  },
  trips: {
    src: "/assets/phone-screen/Trips.png",
    alt: "The Trips screen in Twofold, listing upcoming and past journeys",
    width: 1019,
  },
  "couple-games": {
    src: "/assets/phone-screen/Game-Screen.png",
    alt: "Twofold's couple games, showing the available question decks",
    width: 1019,
  },
  "widgets-live-activities": {
    src: "/assets/phone-screen/Live-Activities.png",
    alt: "A Twofold Live Activity on the iPhone Lock Screen, tracking a partner's flight",
    width: 1133,
  },
};

// Hand-built illustration per feature, keyed by slug. Features themselves are editable in
// Studio (add/remove/rename/reorder), but the artwork is bespoke JSX - so a feature added
// there, or one whose slug was changed, renders the generic card at the bottom until
// someone adds a matching `case` here.
function FeatureArt({ feature }: { feature: ResolvedFeature }) {
  switch (feature.slug) {
    // `relationship-globe` had a hand-built globe mock here. That feature was replaced by
    // `trips`, which has a real screenshot in FEATURE_SHOTS and so never reaches this switch.
    // Nothing renders .mock-globe/.mock-dot any more now that the home page's globe showcase
    // is a pricing preview; the rules are left in marketing.css so restoring either is a
    // markup change rather than a rewrite.
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
    // No screenshot for this one: the export is a document, not a screen, so the mock below
    // sells it better than a capture of the Settings row that produces it would.
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
    default:
      return (
        <div className="mock-card" style={{ maxWidth: 220 }}>
          <div className="mock-card-row">
            <span className="icon-dot" style={{ background: "var(--sky-blue)" }}>
              <svg className="icon">
                <use href={`/assets/icons.svg#${feature.icon}`} />
              </svg>
            </span>
            <div style={{ fontWeight: 700, fontSize: 14 }}>{feature.title}</div>
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
  const features = resolveFeatures(await getFeatures());

  return (
    <>
      <header className="page-head">
        <Reveal className="wrap">
          <span className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            Features
          </span>
          <h1>Everything your distance deserves</h1>
          <p className="lead">Twofold isn&apos;t just a flight tracker - it&apos;s a shared home for your relationship, wherever in the world you both are.</p>
        </Reveal>
      </header>

      <section style={{ paddingTop: 30 }}>
        <div className="wrap">
          {features.map((feature, index) => {
            return (
              <Reveal key={feature.slug} className={`feature-row${index % 2 === 1 ? " flip" : ""}`}>
                <div className="fr-text">
                  <div className={`icon-badge ${feature.tone}`}>
                    <svg className="icon">
                      <use href={`/assets/icons.svg#${feature.icon}`} />
                    </svg>
                  </div>
                  <h2>{feature.title}</h2>
                  <p className="desc">{feature.detailDescription}</p>
                  <ul className="check-list">
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
                {FEATURE_SHOTS[feature.slug] ? (
                  <div className="feature-shot">
                    <Image
                      src={FEATURE_SHOTS[feature.slug].src}
                      alt={FEATURE_SHOTS[feature.slug].alt}
                      width={FEATURE_SHOTS[feature.slug].width}
                      height={SHOT_HEIGHT}
                      className="app-shot"
                      sizes="(max-width: 820px) 80vw, 380px"
                    />
                  </div>
                ) : (
                  <div className="media-frame">
                    <FeatureArt feature={feature} />
                  </div>
                )}
              </Reveal>
            );
          })}
        </div>
      </section>

      <section className="cta-band" style={{ paddingTop: 0 }}>
        <Reveal className="wrap">
          <div className="card">
            <h2>Start closing the distance</h2>
            <p>Either partner&apos;s subscription unlocks everything for you both.</p>
            <Link className="btn btn-primary btn-lg" href="/pricing">
              See pricing
              <svg className="icon">
                <use href="/assets/icons.svg#icon-arrow-right" />
              </svg>
            </Link>
          </div>
        </Reveal>
      </section>
    </>
  );
}
