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
    slug: "relationship-globe",
    title: "Relationship Globe",
    teaserDescription:
      "An interactive 3D globe showing both of you - your current distance apart, and every trip you've taken to close it.",
    detailDescription:
      "The centre of Twofold is an interactive 3D globe showing both of you - where you are, the distance between you right now, and every journey you've taken to close it.",
    bullets: [
      "See your current distance apart, updated automatically",
      "Rotate and zoom into cities to explore memories",
      "Every reunion trip draws a new line across your shared history",
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
  // TEMP: Relationship Record (the PDF export) is pulled from the first release. Its entry
  // point in the app is commented out in SettingsView.swift, so nothing should advertise it
  // while it's unreachable. To restore the feature everywhere, put this entry back and also:
  //   - re-create the Sanity `feature-relationship-record` doc: `node scripts/seed-sanity.mjs`
  //     (its FEATURE_SEED/FEATURE_COPY entries are commented out there too)
  //   - re-add the "Relationship Record PDF export" bullet to `plan-premium` in Studio,
  //     and to PLANS.premium.features in config.ts
  //   - restore the export sentence in quizResult-premium (Studio) and in
  //     RelationshipQuiz.tsx's FALLBACK_RESULTS.premium
  //   - restore the Plus-vs-Premium answer in Supabase `faq_entries` (Studio → FAQ tool) and
  //     in faqFallback.ts
  //   - uncomment the "relationship-record" case in (marketing)/features/page.tsx's FeatureArt
  // {
  //   slug: "relationship-record",
  //   title: "Relationship Record",
  //   teaserDescription: "Export a beautifully laid-out PDF keepsake of every trip, memory, and mile you've travelled for each other.",
  //   detailDescription:
  //     "Export a beautifully laid-out PDF of every trip, memory, and mile you've travelled for each other - a keepsake of your long-distance story, ready to print or save.",
  //   bullets: [
  //     "Every trip, flight, and memory in one document",
  //     "Beautifully designed, ready to print",
  //     "Included with Twofold Premium",
  //   ],
  //   icon: "icon-file-download",
  //   tone: "tone-sky",
  // },
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
