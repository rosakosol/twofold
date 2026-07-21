import { defineConfig } from "sanity";
import { structureTool } from "sanity/structure";
import { visionTool } from "@sanity/vision";
import { schemaTypes } from "@/sanity/schemaTypes";
import { structure } from "@/sanity/deskStructure";

// Editing UI for twofoldapp.com.au's marketing copy — hero text, feature copy, FAQ
// entries, and the two legal pages. Embedded at /studio (next-sanity) rather than a
// separate Sanity Studio project, now that the marketing site lives in this same
// Next.js app. Layout, nav, and all Stripe/RevenueCat pricing stay hardcoded in the
// site itself — see src/lib/marketing/faqFallback.ts and featuresFallback.ts for the
// boundary between what's editable here vs. what lives in code.
export default defineConfig({
  name: "default",
  title: "Twofold Website",
  basePath: "/studio",

  projectId: process.env.NEXT_PUBLIC_SANITY_PROJECT_ID!,
  dataset: process.env.NEXT_PUBLIC_SANITY_DATASET!,

  plugins: [structureTool({ structure }), visionTool()],

  schema: {
    types: schemaTypes,
  },
});
