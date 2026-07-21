"use client";

import { NextStudio } from "next-sanity/studio";
import config from "@/sanity/config";

// Embedded Sanity Studio — real Sanity account sign-in here, unrelated to this app's
// own Supabase auth. Not gated by is_feedback_admin() (a separate access model:
// Sanity project membership, managed in the Sanity dashboard) — see AdminNav.tsx for
// the internal-admin link into this. Deliberately NOT statically generated — the
// Studio is a fully client-rendered SPA-style tool that doesn't support SSG/SSR.
export default function StudioPage() {
  return <NextStudio config={config} />;
}
