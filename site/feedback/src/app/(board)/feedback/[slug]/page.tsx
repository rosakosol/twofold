import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FEATURE_DETAIL_SELECT, type FeatureDetail } from "@/lib/queries/useFeature";
import { FeatureDetailView } from "@/components/feedback/FeatureDetailView";

interface PageProps {
  params: Promise<{ slug: string }>;
}

async function getFeature(slug: string): Promise<FeatureDetail | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("feature_requests")
    .select(FEATURE_DETAIL_SELECT)
    .eq("slug", slug)
    .single();
  return (data as unknown as FeatureDetail) ?? null;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params;
  const feature = await getFeature(slug);

  if (!feature) return { title: "Not found" };

  const description = feature.description || `Vote on "${feature.title}" — a feature request for Twofold.`;
  // Plain title here — the root layout's template ("%s | Twofold Feedback") appends the
  // suffix automatically. openGraph/twitter titles are separate fields Next.js does NOT
  // run through that template, so they need the full string spelled out themselves.
  const fullTitle = `${feature.title} | Twofold Feedback`;

  return {
    title: feature.title,
    description,
    openGraph: { title: fullTitle, description, type: "article" },
    twitter: { card: "summary", title: fullTitle, description },
  };
}

export default async function FeatureDetailPage({ params }: PageProps) {
  const { slug } = await params;
  const feature = await getFeature(slug);

  if (!feature) notFound();

  return <FeatureDetailView initialFeature={feature} />;
}
