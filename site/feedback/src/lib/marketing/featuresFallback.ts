import type { FeatureSlug } from "@/lib/marketing/config";
import type { FeatureDoc } from "@/lib/marketing/sanity";

// Icon/tone are readOnly in the Sanity schema (feature.ts) — fixed per slot, not
// editor-controlled — so they live here as plain data rather than coming from Sanity.
// Shared by both the home page's teaser grid and features/page.tsx's detail sections
// (the old site had this duplicated across cms-home.js/cms-features.js; consolidated).
export const FEATURE_ICON: Record<FeatureSlug, string> = {
  "relationship-globe": "icon-globe",
  "live-flight-tracking": "icon-plane",
  memories: "icon-pin",
  "couple-games": "icon-gamepad",
  "widgets-live-activities": "icon-grid",
  "relationship-record": "icon-file-download",
};

export const FEATURE_TONE: Record<FeatureSlug, string> = {
  "relationship-globe": "tone-sky",
  "live-flight-tracking": "tone-sky",
  memories: "tone-red",
  "couple-games": "tone-green",
  "widgets-live-activities": "tone-ink",
  "relationship-record": "tone-sky",
};

// Ported verbatim from the old static features.html / index.html — used per-feature
// only when Sanity has nothing published for that feature's fixed document id yet.
export const FEATURES_FALLBACK: Record<FeatureSlug, Required<Pick<FeatureDoc, "title" | "teaserDescription" | "detailDescription" | "bullets">>> = {
  "relationship-globe": {
    title: "Relationship Globe",
    teaserDescription:
      "An interactive 3D globe showing both of you — your current distance apart, and every trip you've taken to close it.",
    detailDescription:
      "The centre of Twofold is an interactive 3D globe showing both of you — where you are, the distance between you right now, and every journey you've taken to close it.",
    bullets: [
      "See your current distance apart, updated automatically",
      "Rotate and zoom into cities to explore memories",
      "Every reunion trip draws a new line across your shared history",
    ],
  },
  "live-flight-tracking": {
    title: "Live Flight Tracking",
    teaserDescription: "Follow each other's flights in real time — status, gate, delays, and a notification the moment they land.",
    detailDescription:
      "Follow each other's flights in real time. Twofold tells you the moment they take off, and sends a notification the second they land safely.",
    bullets: [
      "Real-time status, gate, and delay updates",
      "“Landed” notifications the moment they're on the ground",
      "Live Activity on the Lock Screen for the whole flight",
    ],
  },
  memories: {
    title: "Memories",
    teaserDescription: "Save photos and moments to the exact places they happened, building a map of your shared story.",
    detailDescription:
      "Save photos and moments to the exact places they happened. Over time, your globe fills with pins — a map of everywhere your story has taken you.",
    bullets: [
      "Attach photos and notes to any location",
      "Revisit memories by zooming into the globe",
      "Private to your relationship — never public",
    ],
  },
  "couple-games": {
    title: "Couple Games",
    teaserDescription: "Bite-sized questions and games built for two, made to close the distance even when apart.",
    detailDescription:
      "Bite-sized questions and games built for two, made to close the distance even when you can't be in the same room — from quick “this or that” rounds to deeper discussion prompts.",
    bullets: [
      "500+ questions and games, 2000+ on Premium",
      "Play async — answer whenever you both have a moment",
      "New topics and decks added regularly",
    ],
  },
  "widgets-live-activities": {
    title: "Widgets & Live Activities",
    teaserDescription: "Keep your relationship on your Home Screen and Lock Screen, always in view.",
    detailDescription:
      "Keep your relationship on your Home Screen and Lock Screen — a countdown to your next reunion, today's distance apart, or a live flight tracker while they're in the air.",
    bullets: [
      "Countdown, distance, and flight-status widgets",
      "Live Activities for in-progress flights",
      "More widget styles unlocked on Premium",
    ],
  },
  "relationship-record": {
    title: "Relationship Record",
    teaserDescription: "Export a beautifully laid-out PDF keepsake of every trip, memory, and mile you've travelled for each other.",
    detailDescription:
      "Export a beautifully laid-out PDF of every trip, memory, and mile you've travelled for each other — a keepsake of your long-distance story, ready to print or save.",
    bullets: [
      "Every trip, flight, and memory in one document",
      "Beautifully designed, ready to print",
      "Included with Twofold Premium",
    ],
  },
};

export function featureWithFallback(slug: FeatureSlug, doc: FeatureDoc | undefined) {
  const fallback = FEATURES_FALLBACK[slug];
  return {
    title: doc?.title || fallback.title,
    teaserDescription: doc?.teaserDescription || fallback.teaserDescription,
    detailDescription: doc?.detailDescription || fallback.detailDescription,
    bullets: doc?.bullets && doc.bullets.length === 3 ? doc.bullets : fallback.bullets,
  };
}
