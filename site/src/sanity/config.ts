import { defineConfig } from "sanity";
import { structureTool } from "sanity/structure";
import { schemaTypes } from "@/sanity/schemaTypes";
import { structure } from "@/sanity/deskStructure";

// Editing UI for twofoldapp.com.au's marketing copy: plan cards, the quiz and the two legal pages.
// The home page, the features and the pricing comparison table are in code
// (docs/TWOFOLD_WEBSITE.md), as are layout, nav and all Stripe/RevenueCat wiring.
//
// Hosted by Sanity (sanity.cli.ts, `npx sanity deploy` from site/), not embedded in the site. It
// used to be mounted at /studio, on the same origin as the console, so anything running in Studio
// could read the console's Supabase session. It now has no Supabase access at all: the FAQ, which
// lives in Supabase, is edited in the console at /admin/faq.
//
// No Vision (@sanity/vision): a raw query box is a developer tool, and every editor would have it.
// Run queries from `npx sanity documents query` or sanity.io/manage instead.
//
// The NEXT_PUBLIC_ names are kept so the site's .env.local serves both; sanity.cli.ts hands them to
// the Studio build.
export default defineConfig({
  name: "default",
  title: "Twofold Website",

  projectId: process.env.NEXT_PUBLIC_SANITY_PROJECT_ID!,
  dataset: process.env.NEXT_PUBLIC_SANITY_DATASET!,

  plugins: [structureTool({ structure })],

  schema: {
    types: schemaTypes,
  },
});
