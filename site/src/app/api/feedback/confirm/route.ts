import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createZohoTransport } from "@/lib/mail/zoho";
import { renderTemplate, extractSubject } from "@/lib/mail/renderTemplate";
import { escapeHtml } from "@/lib/mail/escapeHtml";
import { SITE_URL } from "@/lib/mail/companyInfo";
import { listUnsubscribeHeaders, PREFERENCES_URL, unsubscribeUrl } from "@/lib/mail/unsubscribe";
import { CATEGORY_LABELS, type FeatureCategory } from "@/lib/utils/constants";

/**
 * The "Your idea is on the board" email, sent after somebody posts a feature request.
 *
 * The browser asks; the database decides. `claim_feedback_confirmation` runs as the signed-in
 * person and returns a row only for their own request, posted in the last hour, not confirmed
 * before, to an address that has not turned feedback updates off (20261112000000). Anything else
 * is a quiet no-op, so this cannot be used to send mail to anyone, or to send it twice.
 */
export async function POST(request: Request) {
  let featureId: unknown;
  try {
    ({ featureId } = await request.json());
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }
  if (typeof featureId !== "string") {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("claim_feedback_confirmation", { p_feature_id: featureId });
  const row = Array.isArray(data) ? data[0] : null;
  if (error || !row) {
    return NextResponse.json({ ok: true, sent: false });
  }

  let mailer: ReturnType<typeof createZohoTransport>;
  try {
    mailer = createZohoTransport();
  } catch (err) {
    console.warn("[feedback] Zoho SMTP not configured, skipping confirmation:", (err as Error).message);
    return NextResponse.json({ ok: true, sent: false });
  }
  const { transport, sender } = mailer;

  const description = row.description.trim();
  const html = renderTemplate("feedback-received", {
    Name: escapeHtml(row.display_name),
    Title: escapeHtml(row.title),
    Description: escapeHtml(description.length > 240 ? `${description.slice(0, 239)}…` : description),
    Category: escapeHtml(CATEGORY_LABELS[row.category as FeatureCategory] ?? row.category),
    RequestURL: escapeHtml(`${SITE_URL}/feedback?q=${encodeURIComponent(row.title)}`),
    UnsubscribeURL: escapeHtml(unsubscribeUrl(row.token, "feedback_updates")),
    PreferencesURL: escapeHtml(PREFERENCES_URL),
  });

  try {
    await transport.sendMail({
      ...sender("announcement"),
      to: row.email,
      subject: extractSubject(html),
      html,
      headers: listUnsubscribeHeaders(row.token, "feedback_updates"),
    });
  } catch (err) {
    // The reason only: a nodemailer error carries the envelope, address included.
    console.error("[feedback] confirmation failed:", (err as Error)?.message ?? "unknown");
    return NextResponse.json({ ok: true, sent: false });
  } finally {
    transport.close();
  }
  return NextResponse.json({ ok: true, sent: true });
}
