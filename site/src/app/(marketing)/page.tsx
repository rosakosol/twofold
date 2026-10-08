import fs from "node:fs";
import path from "node:path";
import Image, { getImageProps } from "next/image";
import Link from "next/link";
import { Download, Heart, Lock, Moon, Plane, PlaneLanding, Sun, Users } from "lucide-react";
import "./home.css";
import { AppStoreButton } from "@/components/site/AppStoreButton";
import { PhoneMockup } from "@/components/site/PhoneMockup";
import { HomePlans } from "@/components/marketing/HomePlans";
import { StatusPill } from "@/components/site/StatusPill";
import {
  AppNotification,
  CountdownWidget,
  DailyQuestionWidget,
  DrawingPadWidget,
  FlightLiveActivity,
  StreakRow,
} from "@/components/site/ProductVisuals";
import { WaitlistForm } from "@/components/marketing/WaitlistForm";
import { getResolvedPlans } from "@/lib/marketing/sanity";
import { PHONE_SHOT_HEIGHT, PHONE_SHOT_WIDTH, phoneScreenSrc } from "@/lib/marketing/phoneScreens";

// The home page (docs/TWOFOLD_WEBSITE.md, section 4). Its copy is the spec's, word for word.

/** The hero's couple photo, 600x720 or larger. Until it is in public/, the hero shows the app's
 *  Home screen in a phone instead, with the same notification and widget around it. */
const HERO_PHOTO = "/assets/home/hero-couple.jpg";
const hasHeroPhoto = fs.existsSync(path.join(process.cwd(), "public", HERO_PHOTO));

type TimePill = { icon: "sun" | "moon" | "plane" | "landing"; label: string };

const TIME_ICONS = { sun: Sun, moon: Moon, plane: Plane, landing: PlaneLanding };

function TimePills({ pills }: { pills: TimePill[] }) {
  return (
    <div className="home-day-times">
      {pills.map((pill) => {
        const Icon = TIME_ICONS[pill.icon];
        return (
          <StatusPill key={pill.label} tone="surface" icon={<Icon />} className="pill-raised">
            {pill.label}
          </StatusPill>
        );
      })}
    </div>
  );
}

/** The memories map of Rome: the app's own Memories screen, cropped to the map, light or dark. */
function RomeMap() {
  const common = {
    alt: "The Memories map of Rome, with photo pins where their memories happened",
    width: PHONE_SHOT_WIDTH,
    height: PHONE_SHOT_HEIGHT,
    sizes: "(max-width: 900px) 90vw, 560px",
  };
  const { props: light } = getImageProps({ ...common, src: phoneScreenSrc("memories-map", "light") });
  const { props: dark } = getImageProps({ ...common, src: phoneScreenSrc("memories-map", "dark") });
  // Both captures, the page's theme showing one: see PhoneMockup. Lazy, so the other is not fetched.
  return (
    <div className="home-map">
      {/* eslint-disable-next-line @next/next/no-img-element -- getImageProps output */}
      <img {...light} alt={common.alt} loading="lazy" className="home-map-shot theme-light-only" />
      {/* eslint-disable-next-line @next/next/no-img-element -- getImageProps output */}
      <img {...dark} alt={common.alt} loading="lazy" className="home-map-shot theme-dark-only" />
      <figure className="home-quote">
        {/* eslint-disable-next-line @next/next/no-img-element -- small fixed thumbnail */}
        <img src="/assets/home/first-date.webp" alt="" width={56} height={56} />
        <div>
          <blockquote>&ldquo;You were wearing a red sundress and I couldn&rsquo;t stop looking at you.&rdquo;</blockquote>
          <figcaption>
            <strong>Our first date</strong>
            <span>Trattoria Pizzeria Luzzi, Rome</span>
          </figcaption>
        </div>
      </figure>
    </div>
  );
}

export default async function HomePage() {
  const plans = await getResolvedPlans();

  return (
    <>
      {/* 1. Hero */}
      <section className="home-hero" aria-labelledby="home-title">
        <div className="page-wrap home-hero-grid">
          <div className="home-hero-copy">
            <StatusPill tone="surface" icon={<Heart />} className="pill-coral-icon">
              Made for couples doing long distance
            </StatusPill>
            <h1 id="home-title">Stay close, no matter the distance.</h1>
            <p className="lead">
              You&rsquo;re in one city, they&rsquo;re in another. Twofold keeps you in each other&rsquo;s day: what time it is over
              there, which flight they&rsquo;re on, and how many sleeps until the next hello.
            </p>
            <div className="home-hero-actions">
              <AppStoreButton size="lg" />
              <Link className="btn btn-secondary btn-lg" href="/quiz">
                Find your plan
              </Link>
            </div>
            <p className="home-hero-note">
              <Lock aria-hidden />
              Encrypted, and only visible to your partner
            </p>
          </div>

          <div className={`home-hero-art${hasHeroPhoto ? "" : " is-phone"}`}>
            {hasHeroPhoto ? (
              <figure className="home-hero-photo">
                <Image
                  src={HERO_PHOTO}
                  alt="Alex and Sam together in Lisbon at sunset"
                  width={600}
                  height={720}
                  sizes="(max-width: 900px) 90vw, 600px"
                  preload
                />
                <figcaption>
                  <strong>Alex and Sam</strong>
                  <span>Lisbon, after 62 days apart</span>
                </figcaption>
              </figure>
            ) : (
              <PhoneMockup screen="home" eager sizes="(max-width: 900px) 64vw, 340px" className="home-hero-phone" />
            )}
            <AppNotification
              className="home-hero-notification"
              title="Alex answered today's question"
              body="Your turn. Keep your 47-day streak going."
            />
            <CountdownWidget className="home-hero-countdown" />
          </div>
        </div>
      </section>

      {/* 2. Distance */}
      <section className="home-distance" aria-labelledby="distance-title">
        <div className="page-wrap">
          <div className="home-arc">
            <svg viewBox="0 0 1200 300" aria-hidden className="home-arc-svg">
              <path className="home-arc-track" d="M60 250 Q600 -30 1140 250" pathLength={1} />
              <path className="home-arc-progress" d="M60 250 Q600 -30 1140 250" pathLength={1} />
              {/* The plane at 62% of the way, turned along the curve. */}
              <g transform="translate(729.6 118.1) rotate(7)">
                <circle r="22" className="home-arc-plane-bg" />
                <path className="home-arc-plane" d="M-12 0 L-4 -2 L2 -11 L6 -11 L3 -2 L10 -2 L13 -6 L15 -6 L14 0 L15 6 L13 6 L10 2 L3 2 L6 11 L2 11 L-4 2 Z" />
              </g>
            </svg>
            <span className="home-arc-end is-start">
              <span className="pv-avatar pv-avatar-alex" aria-hidden>A</span>
              <span>Alex, Rome</span>
            </span>
            <span className="home-arc-end is-end">
              <span>Sam, Melbourne</span>
              <span className="pv-avatar pv-avatar-sam" aria-hidden>S</span>
            </span>
            <StatusPill tone="accent" icon={<Plane />} className="home-arc-chip">
              Alex is in the air
            </StatusPill>
          </div>
          <h2 id="distance-title" className="home-distance-number">
            15,966 km
          </h2>
          <p className="home-distance-line">
            Between Alex and Sam tonight. Twofold keeps count, and the number shrinks every time one of them boards.
          </p>
        </div>
      </section>

      {/* 3. Your day, across two time zones */}
      <section className="home-section" aria-labelledby="day-title">
        <div className="page-wrap">
          <header className="home-section-head">
            <h2 id="day-title">Your day, across two time zones</h2>
            <p className="lead">However many hours sit between you, this is how Twofold fills them.</p>
          </header>
          <div className="home-day-grid">
            <article className="home-day-card">
              <TimePills pills={[{ icon: "sun", label: "7:24 am, your time" }, { icon: "moon", label: "11:24 pm, theirs" }]} />
              <h3>Wake up to your partner&rsquo;s drawing</h3>
              <p>They leave a note on the shared drawing pad before bed. It&rsquo;s on your Home Screen before your alarm goes off.</p>
              <div className="home-day-visual">
                <DrawingPadWidget />
              </div>
            </article>
            <article className="home-day-card">
              <TimePills pills={[{ icon: "moon", label: "8:00 pm, yours" }, { icon: "sun", label: "12:00 pm, theirs" }]} />
              <h3>Answer one question, together</h3>
              <p>A deep question every day keeps you talking about more than how the day went, and keeps your streak alive.</p>
              <div className="home-day-visual is-stack">
                <DailyQuestionWidget />
                <StreakRow />
              </div>
            </article>
            <article className="home-day-card">
              <TimePills pills={[{ icon: "moon", label: "11:40 pm, theirs" }, { icon: "plane", label: "Departure day" }]} />
              <h3>Watch them cross the world</h3>
              <p>Every gate change and delay, live on your Lock Screen, right up until it says they&rsquo;ve landed.</p>
              <div className="home-day-visual is-dark">
                <FlightLiveActivity />
              </div>
            </article>
            <article className="home-day-card">
              <TimePills pills={[{ icon: "landing", label: "Arrivals" }]} />
              <h3>Save it right where it happened</h3>
              <p>Photos and notes pinned to the map, so the story of the two of you has places in it.</p>
              <div className="home-day-visual is-map">
                <RomeMap />
              </div>
            </article>
          </div>
        </div>
      </section>

      {/* 4. How it works */}
      <section className="home-section" aria-labelledby="how-title">
        <div className="page-wrap">
          <header className="home-section-head">
            <h2 id="how-title">From miles apart to one shared map</h2>
            <p className="lead">
              No spreadsheets, no guessing when they&rsquo;ll land. Pair once, add your plans, and Twofold keeps you both up to date.
            </p>
          </header>
          <ol className="home-steps">
            <li>
              <PhoneMockup screen="connected" sizes="(max-width: 760px) 62vw, 260px" />
              <span className="home-step-number" aria-hidden>1</span>
              <h3>Connect with your partner</h3>
              <p>Send one invite link. Everything you add from then on belongs to both of you.</p>
            </li>
            <li>
              <PhoneMockup screen="travel-flights" sizes="(max-width: 760px) 62vw, 260px" />
              <span className="home-step-number" aria-hidden>2</span>
              <h3>Add your trips and flights</h3>
              <p>Add a flight in seconds. Twofold tracks its status and tells your partner the moment you land.</p>
            </li>
            <li>
              <PhoneMockup screen="travel-trips" sizes="(max-width: 760px) 62vw, 260px" />
              <span className="home-step-number" aria-hidden>3</span>
              <h3>Watch your globe grow</h3>
              <p>Every trip to see each other draws a new line across your shared globe.</p>
            </li>
          </ol>
        </div>
      </section>

      {/* 5. Trust strip */}
      <section className="home-trust-section" aria-label="Privacy and billing">
        <div className="page-wrap">
          <ul className="home-trust">
            <li>
              <span className="home-trust-icon" aria-hidden>
                <Lock />
              </span>
              <span>
                <strong>Private by default</strong>
                <span>Your data is encrypted and only visible to your partner.</span>
              </span>
            </li>
            <li>
              <span className="home-trust-icon" aria-hidden>
                <Download />
              </span>
              <span>
                <strong>Yours to export</strong>
                <span>Download your data as CSV whenever you like.</span>
              </span>
            </li>
            <li>
              <span className="home-trust-icon" aria-hidden>
                <Users />
              </span>
              <span>
                <strong>One bill for two</strong>
                <span>Either partner subscribes and you both get everything.</span>
              </span>
            </li>
          </ul>
        </div>
      </section>

      {/* 6. Pricing summary */}
      <section className="home-section" aria-labelledby="pricing-title">
        <div className="page-wrap">
          <HomePlans plans={plans} />
          <p className="home-compare">
            <Link className="btn-link" href="/pricing#compare">
              Compare plans in full
            </Link>
          </p>
        </div>
      </section>

      {/* 7. Quiz and Android waitlist */}
      <section className="home-section" aria-label="Find your plan, or join the Android waitlist">
        <div className="page-wrap home-pair">
          <article id="quiz" className="home-pair-card" aria-labelledby="quiz-title">
            <h2 id="quiz-title">Which plan fits your relationship?</h2>
            <p>Answer five quick questions about how you two do long distance and we&rsquo;ll point you to the right plan.</p>
            <Link className="btn btn-primary" href="/quiz">
              Take the quiz
            </Link>
          </article>
          <article id="waitlist" className="home-pair-card" aria-labelledby="waitlist-title">
            <h2 id="waitlist-title">Twofold for Android is next</h2>
            <p>Leave your email and we&rsquo;ll send one message when it ships.</p>
            <WaitlistForm />
          </article>
        </div>
      </section>
    </>
  );
}
