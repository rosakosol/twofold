import { readFile } from "node:fs/promises";
import path from "node:path";
import { ImageResponse } from "next/og";
import { createClient } from "@/lib/supabase/server";
import { STATUS_LABELS, CATEGORY_LABELS, type FeatureStatus, type FeatureCategory } from "@/lib/utils/constants";

export const runtime = "nodejs";
export const alt = "Twofold Feedback";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const supabase = await createClient();
  const { data: feature } = await supabase
    .from("feature_requests")
    .select("title, status, category, upvote_count")
    .eq("slug", slug)
    .single();

  const iconBuffer = await readFile(path.join(process.cwd(), "public", "app-icon.png"));
  const iconDataUrl = `data:image/png;base64,${iconBuffer.toString("base64")}`;

  const title = feature?.title ?? "Twofold Feedback";
  const statusLabel = feature ? STATUS_LABELS[feature.status as FeatureStatus] : null;
  const categoryLabel = feature ? CATEGORY_LABELS[feature.category as FeatureCategory] : null;

  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "72px",
          background: "linear-gradient(135deg, #d9eef9 0%, #e4f4e6 100%)",
          fontFamily: "Inter, sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={iconDataUrl} width={64} height={64} style={{ borderRadius: 16 }} alt="" />
          <span style={{ fontSize: 32, fontWeight: 600, color: "#1c2a38" }}>Twofold Feedback</span>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
          <div
            style={{
              fontSize: 56,
              fontWeight: 600,
              color: "#1c2a38",
              lineHeight: 1.2,
              display: "-webkit-box",
              maxWidth: 980,
            }}
          >
            {title}
          </div>

          <div style={{ display: "flex", gap: 16 }}>
            {statusLabel && (
              <div
                style={{
                  fontSize: 26,
                  color: "#ffffff",
                  background: "#4fa9e0",
                  padding: "10px 24px",
                  borderRadius: 999,
                  display: "flex",
                }}
              >
                {statusLabel}
              </div>
            )}
            {categoryLabel && (
              <div
                style={{
                  fontSize: 26,
                  color: "#1c2a38",
                  background: "rgba(28, 42, 56, 0.08)",
                  padding: "10px 24px",
                  borderRadius: 999,
                  display: "flex",
                }}
              >
                {categoryLabel}
              </div>
            )}
            {feature && (
              <div
                style={{
                  fontSize: 26,
                  color: "#ffffff",
                  background: "#e85c6b",
                  padding: "10px 24px",
                  borderRadius: 999,
                  display: "flex",
                }}
              >
                {feature.upvote_count} votes
              </div>
            )}
          </div>
        </div>
      </div>
    ),
    { ...size }
  );
}
