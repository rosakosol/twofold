import Link from "next/link";
import { Reveal } from "@/components/marketing/Reveal";
import { FeatureTeaserGrid } from "@/components/marketing/FeatureTeaserGrid";
import { RelationshipQuiz } from "@/components/marketing/RelationshipQuiz";
import { WaitlistForm } from "@/components/marketing/WaitlistForm";
import { getHero, getFeatures, getQuizQuestions, getQuizResults } from "@/lib/marketing/sanity";
import { APP_STORE_URL, PLANS, FEATURE_SLUGS } from "@/lib/marketing/config";

export default async function HomePage() {
  const [hero, featureDocs, quizQuestions, quizResults] = await Promise.all([
    getHero(),
    getFeatures(FEATURE_SLUGS),
    getQuizQuestions(),
    getQuizResults(),
  ]);

  const headline = hero?.headline || "See how far you've gone\nfor each other.";
  const eyebrow = hero?.eyebrow || "Built for long-distance couples";
  const subtext =
    hero?.subtext ||
    "Twofold turns your long-distance relationship into a living map — track flights in real time, watch the distance between you close, and relive every trip you've taken just to be together.";
  const heroNote = hero?.heroNote || "Private by default — only your partner ever sees your journeys.";

  return (
    <>
      <section className="hero">
        <div className="wrap hero-inner">
          <div className="hero-copy">
            <p className="eyebrow">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-heart" />
              </svg>
              <span>{eyebrow}</span>
            </p>
            <h1>
              {headline.split("\n").map((line, i, arr) => (
                <span key={i}>
                  {line}
                  {i < arr.length - 1 && <br />}
                </span>
              ))}
            </h1>
            <p className="lede">{subtext}</p>
            <div className="cta-row">
              <a className="appstore-badge hide-on-desktop" data-appstore-link href={APP_STORE_URL} aria-label="Download Twofold on the App Store">
                <svg className="icon">
                  <use href="/assets/icons.svg#icon-apple" />
                </svg>
                <span className="badge-text">
                  <small>Download on the</small>
                  <strong>App&nbsp;Store</strong>
                </span>
              </a>
              <Link className="btn btn-primary btn-lg hide-on-mobile" href="/pricing">
                Get started
                <svg className="icon">
                  <use href="/assets/icons.svg#icon-arrow-right" />
                </svg>
              </Link>
              <a className="appstore-badge hide-on-mobile" data-appstore-link href={APP_STORE_URL} aria-label="Download Twofold on the App Store">
                <svg className="icon">
                  <use href="/assets/icons.svg#icon-apple" />
                </svg>
                <span className="badge-text">
                  <small>Download on the</small>
                  <strong>App&nbsp;Store</strong>
                </span>
              </a>
              <Link className="text-link hide-on-desktop" href="/pricing">
                See pricing
              </Link>
            </div>
            <p className="hero-note">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-shield" />
              </svg>
              <span>{heroNote}</span>
            </p>
          </div>
          <div className="hero-art" aria-hidden>
            <div className="art-glow" />
            <div className="art-glow-2" />
            {/* eslint-disable-next-line @next/next/no-img-element -- decorative art, matches ported static markup */}
            <img src="/assets/globe-heart.png" alt="" className="art-globe" />
            <div className="hero-chip hero-chip-1">
              <span className="icon-wrap">
                <svg className="icon">
                  <use href="/assets/icons.svg#icon-plane" />
                </svg>
              </span>
              Landed in Singapore 🇸🇬
            </div>
            <div className="hero-chip hero-chip-2">
              <span className="icon-wrap">
                <svg className="icon">
                  <use href="/assets/icons.svg#icon-pin" />
                </svg>
              </span>
              +1 memory saved
            </div>
          </div>
        </div>
      </section>

      <section className="stat-strip">
        <div className="stat-strip-inner">
          <p>
            <strong>84,392 km</strong> travelled for each other — that&apos;s more than twice around the Earth.
          </p>
        </div>
      </section>

      <section aria-labelledby="how-heading">
        <div className="wrap">
          <div className="section-head reveal">
            <p className="eyebrow">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-sparkle" />
              </svg>
              How it works
            </p>
            <h2 id="how-heading">From &ldquo;miles apart&rdquo; to one shared map</h2>
            <p>No spreadsheets, no guessing when they&apos;ll land. Twofold does the tracking so you can just look forward to seeing each other.</p>
          </div>
          <div className="steps">
            <Reveal className="step-card">
              <span className="step-num">1</span>
              <h3>Connect with your partner</h3>
              <p>Pair your accounts once with an invite link. Everything you share from then on belongs to both of you.</p>
            </Reveal>
            <Reveal className="step-card">
              <span className="step-num">2</span>
              <h3>Share your trips &amp; flights</h3>
              <p>Add a flight or a trip in seconds. Twofold tracks status automatically and tells your partner when you land.</p>
            </Reveal>
            <Reveal className="step-card">
              <span className="step-num">3</span>
              <h3>Watch your globe grow</h3>
              <p>Every journey to see each other draws a new line across your shared globe — a living record of your relationship.</p>
            </Reveal>
          </div>
        </div>
      </section>

      <section aria-labelledby="features-heading">
        <div className="wrap">
          <div className="section-head reveal">
            <p className="eyebrow">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-heart" />
              </svg>
              Everything your distance deserves
            </p>
            <h2 id="features-heading">Built around the two of you</h2>
          </div>
          <FeatureTeaserGrid docs={featureDocs} />
        </div>
      </section>

      <RelationshipQuiz questions={quizQuestions} results={quizResults} />

      <section aria-labelledby="pricing-teaser-heading">
        <div className="wrap">
          <div className="section-head reveal">
            <p className="eyebrow">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-sparkle" />
              </svg>
              Simple pricing
            </p>
            <h2 id="pricing-teaser-heading">Plus for the everyday, Premium for the full globe</h2>
            <p>Start with a plan that fits your relationship — upgrade any time, and either partner&apos;s subscription unlocks it for both of you.</p>
          </div>
          <Reveal className="pricing-grid">
            <div className="price-card">
              <h3>{PLANS.plus.name}</h3>
              <p className="price-tagline">{PLANS.plus.tagline}</p>
              <div className="price-amount">
                <span className="num">{PLANS.plus.yearly.perMonthLabel}</span>
                <span className="period">/mo, billed yearly</span>
              </div>
              <p className="price-sub">or {PLANS.plus.monthly.priceLabel}/month</p>
              <ul className="feature-list">
                {PLANS.plus.features.slice(1, 4).map((feature) => (
                  <li key={feature}>
                    <svg className="icon">
                      <use href="/assets/icons.svg#icon-check" />
                    </svg>
                    {feature}
                  </li>
                ))}
              </ul>
              <Link className="btn btn-outline btn-block" href="/pricing">
                Choose Plus
              </Link>
            </div>
            <div className="price-card is-featured">
              <span className="price-ribbon">Most popular</span>
              <h3>{PLANS.premium.name}</h3>
              <p className="price-tagline">{PLANS.premium.tagline}</p>
              <div className="price-amount">
                <span className="num">{PLANS.premium.yearly.perMonthLabel}</span>
                <span className="period">/mo, billed yearly</span>
              </div>
              <p className="price-sub">or {PLANS.premium.monthly.priceLabel}/month</p>
              <ul className="feature-list">
                {PLANS.premium.features.slice(0, 3).map((feature) => (
                  <li key={feature}>
                    <svg className="icon">
                      <use href="/assets/icons.svg#icon-check" />
                    </svg>
                    {feature}
                  </li>
                ))}
              </ul>
              <Link className="btn btn-primary btn-block" href="/pricing">
                Choose Premium
              </Link>
            </div>
          </Reveal>
        </div>
      </section>

      <section aria-labelledby="cta-heading">
        <div className="cta-banner reveal">
          <h2 id="cta-heading">Start closing the distance today</h2>
          <p>Twofold is free to download, with Plus and Premium unlocking the full experience for both of you.</p>
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

      <section id="waitlist" aria-labelledby="waitlist-heading">
        <div className="wrap">
          <Reveal className="waitlist-card">
            <p className="eyebrow" style={{ justifyContent: "center" }}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-bell" />
              </svg>
              Coming soon
            </p>
            <h2 id="waitlist-heading">Twofold for Android is coming</h2>
            <p>We&apos;re building the Android version next. Leave your email and we&apos;ll let you know the moment it&apos;s ready — no spam, just one message when it ships.</p>
            <WaitlistForm />
          </Reveal>
        </div>
      </section>
    </>
  );
}
