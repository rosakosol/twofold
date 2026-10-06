import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { BookHeart, Check, Gamepad2, Images, LayoutGrid, Plane, Route } from "lucide-react";
import "./features.css";
import { AppStoreButton } from "@/components/site/AppStoreButton";
import { GlowHalo, type HaloTint } from "@/components/site/GlowHalo";
import { PhoneMockup } from "@/components/site/PhoneMockup";
import { StatusPill } from "@/components/site/StatusPill";
import {
  CountdownWidget,
  FlightLiveActivity,
  FlightWidget,
  KeepsakeCover,
  LockScreen,
  WhosMoreLikelyCard,
} from "@/components/site/ProductVisuals";

export const metadata: Metadata = {
  title: "Features",
  description:
    "Everything Twofold gives long-distance couples: memories where they happened, every trip on one shared timeline, live flight tracking, couple games, widgets, and your Relationship Record.",
};

// The features page (docs/TWOFOLD_WEBSITE.md, section 5). Its copy is the spec's, word for word.

type Feature = {
  id: string;
  label: string;
  icon: typeof Images;
  tint: HaloTint;
  heading: string;
  body: string;
  ticks: [string, string, string];
  visual: ReactNode;
};

const PHONE = "(max-width: 760px) 56vw, 260px";

const FEATURES: Feature[] = [
  {
    id: "memories",
    label: "Memories",
    icon: Images,
    tint: "coral",
    heading: "Keep every moment where it happened",
    body: "Save photos and notes to the exact places they happened. Over time your globe fills with pins: a map of everywhere your story has taken you.",
    ticks: ["Attach photos and notes to any place", "Revisit a memory by zooming into your globe", "Private to the two of you, never public"],
    visual: (
      <div className="features-pair">
        <PhoneMockup screen="memory-detail" sizes={PHONE} />
        <PhoneMockup screen="memories-map" sizes={PHONE} />
      </div>
    ),
  },
  {
    id: "trips",
    label: "Trips",
    icon: Route,
    tint: "green",
    heading: "Every journey, on one shared timeline",
    body: "Add a trip in seconds and your partner sees it straight away: where you're going, when you land, and how long until you're in the same place. Work trips and holidays sit on the same timeline as your reunions.",
    ticks: ["Upcoming and past journeys in one shared list", "Business trips, holidays and reunion visits alike", "Every trip draws a new line across your globe"],
    visual: (
      <div className="features-pair">
        <PhoneMockup screen="travel-trips" sizes={PHONE} />
        <PhoneMockup screen="travel-flights" sizes={PHONE} />
      </div>
    ),
  },
  {
    id: "flights",
    label: "Live flight tracking",
    icon: Plane,
    tint: "blue",
    heading: "Know the moment they land",
    body: "Follow each other's flights in real time. Twofold tells you when they take off, and sends a notification the second they touch down.",
    ticks: ["Real-time status, gate and delay updates", "A notification the moment they're on the ground", "A Live Activity on your Lock Screen for the whole flight"],
    visual: (
      <div className="features-with-overlay">
        <PhoneMockup screen="home" sizes={PHONE} />
        <FlightLiveActivity className="features-overlay is-bottom" />
      </div>
    ),
  },
  {
    id: "games",
    label: "Couple games",
    icon: Gamepad2,
    tint: "indigo",
    heading: "Stay curious about each other",
    body: "Bite-sized questions and games made for two, from quick this-or-that rounds to the questions you'd never think to ask over text.",
    ticks: ["500+ questions and games, 2000+ on Premium", "Play async: answer whenever you each have a moment", "New topics and decks added regularly"],
    visual: (
      <div className="features-with-overlay">
        <PhoneMockup screen="games" sizes={PHONE} />
        <WhosMoreLikelyCard className="features-overlay is-side" />
      </div>
    ),
  },
  {
    id: "widgets",
    label: "Widgets and Live Activities",
    icon: LayoutGrid,
    tint: "blue",
    heading: "Keep them on your Home Screen",
    body: "A countdown to your next reunion, today's distance apart, or their flight while they're in the air, right on your Home Screen and Lock Screen.",
    ticks: ["Countdown, distance and flight-status widgets", "Live Activities for flights in progress", "More widget styles on Premium"],
    visual: (
      <div className="features-with-overlay">
        <figure className="phone-mockup">
          <div className="phone-bezel">
            <LockScreen />
          </div>
        </figure>
        <div className="features-overlay is-stack">
          <CountdownWidget />
          <FlightWidget />
        </div>
      </div>
    ),
  },
  {
    id: "record",
    label: "Relationship Record",
    icon: BookHeart,
    tint: "paper",
    heading: "Your story, kept in one place",
    body: "Export your whole relationship as a beautifully formatted document: every trip you've taken, every memory you've saved, every flight you've flown to be together. One keepsake to print, save or share.",
    ticks: ["Every trip, memory and flight on one timeline", "Formatted and ready to print or present", "Included with Twofold Premium"],
    visual: (
      <div className="features-with-overlay">
        <PhoneMockup screen="our-story" sizes={PHONE} />
        <KeepsakeCover className="features-overlay is-side" />
      </div>
    ),
  },
];

export default function FeaturesPage() {
  return (
    <>
      <section className="features-hero" aria-labelledby="features-title">
        <div className="page-wrap">
          <StatusPill tone="surface" icon={<LayoutGrid />}>
            Features
          </StatusPill>
          <h1 id="features-title">Everything your distance deserves</h1>
          <p className="lead">
            Twofold isn&rsquo;t just a flight tracker. It&rsquo;s a shared home for your relationship, wherever in the world you both
            are.
          </p>
          <nav className="features-chips" aria-label="Features on this page">
            {FEATURES.map(({ id, label, icon: Icon, tint }) => (
              <a key={id} href={`#${id}`} className={`features-chip tint-${tint}`}>
                <Icon aria-hidden />
                {label}
              </a>
            ))}
          </nav>
        </div>
      </section>

      {FEATURES.map(({ id, label, icon: Icon, tint, heading, body, ticks, visual }, index) => (
        <section key={id} id={id} className={`features-row${index % 2 ? " is-flipped" : ""}`} aria-labelledby={`${id}-title`}>
          <div className="page-wrap features-row-grid">
            <div className="features-copy">
              <p className={`features-label tint-${tint}`}>
                <span className="features-label-icon" aria-hidden>
                  <Icon />
                </span>
                {label}
              </p>
              <h2 id={`${id}-title`}>{heading}</h2>
              <p className="features-body">{body}</p>
              <ul className="features-ticks">
                {ticks.map((tick) => (
                  <li key={tick}>
                    <Check aria-hidden />
                    {tick}
                  </li>
                ))}
              </ul>
            </div>
            <GlowHalo tint={tint} className="features-visual">
              {visual}
            </GlowHalo>
          </div>
        </section>
      ))}

      <section className="features-closing-section" aria-labelledby="closing-title">
        <div className="page-wrap">
          <div className="features-closing">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
            <img src="/assets/globe-heart.png" alt="" width={56} height={56} />
            <h2 id="closing-title">Start closing the distance</h2>
            <p>Either partner&rsquo;s subscription unlocks everything for you both.</p>
            <div className="features-closing-actions">
              <AppStoreButton />
              <Link className="btn btn-secondary" href="/pricing">
                See pricing
              </Link>
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
