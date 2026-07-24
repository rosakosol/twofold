import { defineConfig } from "sanity";
import { structureTool } from "sanity/structure";
import { visionTool } from "@sanity/vision";
import { HelpCircleIcon } from "@sanity/icons";
import { schemaTypes } from "@/sanity/schemaTypes";
import { structure } from "@/sanity/deskStructure";
import { FaqTool } from "@/sanity/tools/FaqTool";

// Editing UI for twofoldapp.com.au's marketing copy — hero text, feature copy, and the two
// legal pages — plus the "FAQ" tool below. Embedded at /studio (next-sanity) rather than a
// separate Sanity Studio project, now that the marketing site lives in this same Next.js app.
// Layout, nav, and all Stripe/RevenueCat pricing stay hardcoded in the site itself — see
// src/lib/marketing/faqFallback.ts and featuresFallback.ts for the boundary between what's
// editable here vs. what lives in code.
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

  // FAQ used to be a normal Sanity document type (`faqItem`) here, but content is now shared
  // with the iOS app's Settings > Support screen — a single Supabase table (`faq_entries`) is
  // the source of truth for both, so this custom tool edits that table directly instead of
  // Sanity's own dataset. See src/sanity/tools/FaqTool.tsx.
  tools: (prev) => [...prev, { name: "faq", title: "FAQ", icon: HelpCircleIcon, component: FaqTool }],
});
