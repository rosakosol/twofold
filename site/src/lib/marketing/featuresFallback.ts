import type { FeatureDoc } from "@/lib/marketing/sanity";

export interface ResolvedFeature {
  slug: string;
  title: string;
  teaserDescription: string;
  detailDescription: string;
  bullets: string[];
  /** Symbol id in public/assets/icons.svg, e.g. "icon-globe". */
  icon: string;
  /** CSS class on the icon chip, e.g. "tone-sky". */
  tone: string;
}

// Used only when Sanity has no `feature` documents published at all - copy ported
// verbatim from the old static features.html / index.html. Once anything is published,
// Sanity is the whole list (including how many features there are and their order), so
// this is a cold-start safety net rather than a per-field default.
export const FEATURES_FALLBACK: ResolvedFeature[] = [
  {
    slug: "memories",
    title: "Memories",
    teaserDescription: "Save photos and moments to the exact places they happened, building a map of your shared story.",
    detailDescription:
      "Save photos and moments to the exact places they happened. Over time, your globe fills with pins - a map of everywhere your story has taken you.",
    bullets: [
      "Attach photos and notes to any location",
      "Revisit memories by zooming into the globe",
      "Private to your relationship - never public",
    ],
    icon: "icon-pin",
    tone: "tone-red",
  },
  {
    slug: "trips",
    title: "Trips",
    teaserDescription:
      "Every journey in one shared list - business trips, holidays, and the flights you take just to see each other.",
    detailDescription:
      "Add a trip in seconds and your partner sees it straight away: where you're going, when you land, and how long until you're in the same place. Twofold tracks more than reunions - business travel and holidays go on the same shared timeline.",
    bullets: [
      "Upcoming and past journeys in one shared list",
      "Business trips, holidays, and reunion visits alike",
      "Every trip draws a new line across your shared globe",
    ],
    icon: "icon-globe",
    tone: "tone-sky",
  },
  {
    slug: "live-flight-tracking",
    title: "Live Flight Tracking",
    teaserDescription: "Follow each other's flights in real time - status, gate, delays, and a notification the moment they land.",
    detailDescription:
      "Follow each other's flights in real time. Twofold tells you the moment they take off, and sends a notification the second they land safely.",
    bullets: [
      "Real-time status, gate, and delay updates",
      "“Landed” notifications the moment they're on the ground",
      "Live Activity on the Lock Screen for the whole flight",
    ],
    icon: "icon-plane",
    tone: "tone-sky",
  },
  {
    slug: "couple-games",
    title: "Couple Games",
    teaserDescription: "Bite-sized questions and games built for two, made to close the distance even when apart.",
    detailDescription:
      "Bite-sized questions and games built for two, made to close the distance even when you can't be in the same room - from quick “this or that” rounds to deeper discussion prompts.",
    bullets: [
      "500+ questions and games, 2000+ on Premium",
      "Play async - answer whenever you both have a moment",
      "New topics and decks added regularly",
    ],
    icon: "icon-gamepad",
    tone: "tone-green",
  },
  {
    slug: "widgets-live-activities",
    title: "Widgets & Live Activities",
    teaserDescription: "Keep your relationship on your Home Screen and Lock Screen, always in view.",
    detailDescription:
      "Keep your relationship on your Home Screen and Lock Screen - a countdown to your next reunion, today's distance apart, or a live flight tracker while they're in the air.",
    bullets: [
      "Countdown, distance, and flight-status widgets",
      "Live Activities for in-progress flights",
      "More widget styles unlocked on Premium",
    ],
    icon: "icon-grid",
    tone: "tone-ink",
  },
  // Live, and reachable: Settings -> Your Relationship Record, Premium-gated, built by
  // `CoupleDataExporter.relationshipRecordPDF`. It previously existed only for relationships that
  // had *ended* (Settings -> Disconnect Partner -> Archived Data), which is why it was pulled from
  // the marketing list — the site was promising a living couple something only an ex-couple could
  // get. `ExportHistoryView` and the "Export your story" row this comment used to name are both
  // gone; `RelationshipRecordView` replaced them.
  //
  // Every surface stripped at that time has been restored: the plan bullet in config.ts, the
  // comparison row, the quiz result, faqFallback.ts, and the Supabase `faq_entries` answer.
  //
  // The Sanity copies have NOT — a Studio document overrides the fallback beside it, so wherever
  // one exists it is what renders and these edits change nothing. Still to update in Studio: the
  // `plan-premium` bullet, `quizResult-premium`, the FAQ tool's Plus-vs-Premium answer, and the
  // plan comparison table.
  {
    slug: "relationship-record",
    title: "Relationship Record",
    teaserDescription:
      "Export your whole relationship timeline - every trip, memory, and flight - as a beautifully formatted document.",
    detailDescription:
      "Export your whole relationship timeline as a beautifully formatted document or presentation: every trip you've taken, every memory you've saved, and every flight you've flown to be together, laid out in one keepsake you can print, save, or share.",
    bullets: [
      "Every trip, memory, and flight on one timeline",
      "Beautifully formatted, ready to print or present",
      "Included with Twofold Premium",
    ],
    icon: "icon-file-download",
    tone: "tone-sky",
  },
];

const DEFAULT_ICON = "icon-sparkle";
const DEFAULT_TONE = "tone-sky";

/**
 * Turns whatever Sanity returned into the list the pages render. A doc missing an
 * optional field falls back to the same-slug entry above where one exists (so an editor
 * blanking a field doesn't leave a hole), and to a generic icon/tone for brand-new
 * features that have no counterpart in code.
 */
export function resolveFeatures(docs: FeatureDoc[]): ResolvedFeature[] {
  if (!docs.length) return FEATURES_FALLBACK;

  return docs.flatMap((doc) => {
    const slug = doc.slug;
    // Belt-and-braces: the GROQ query already filters undefined slugs, and the schema
    // requires one - but a slug is what keys the illustration, so never render without.
    if (!slug) return [];
    const fallback = FEATURES_FALLBACK.find((f) => f.slug === slug);
    return [
      {
        slug,
        title: doc.title || fallback?.title || slug,
        teaserDescription: doc.teaserDescription || fallback?.teaserDescription || "",
        detailDescription: doc.detailDescription || fallback?.detailDescription || "",
        bullets: doc.bullets?.length ? doc.bullets : fallback?.bullets ?? [],
        icon: doc.icon ? `icon-${doc.icon}` : fallback?.icon ?? DEFAULT_ICON,
        tone: doc.tone ? `tone-${doc.tone}` : fallback?.tone ?? DEFAULT_TONE,
      },
    ];
  });
}
