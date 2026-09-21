import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { nullableArg } from "@/lib/db/nullableArg";
import { SupportQueue, type SupportRequest } from "@/components/console/SupportQueue";

export const metadata: Metadata = { title: "Support" };
export const dynamic = "force-dynamic";

/**
 * The support inbox.
 *
 * Both contact paths composed an email and kept nothing, so the 48-hour response the app promises
 * for an abuse report rested entirely on somebody reading an inbox, and there was no way to tell
 * whether a request had been answered. The email is still sent, unchanged — it is what actually
 * notifies anyone. This is the record beside it, and now the place it is answered from.
 *
 * No page heading above the inbox: it is a full-height two-pane layout, and a title and a
 * paragraph of explanation above it would push the composer below the fold on a laptop. The name
 * sits in the list rail instead, where a mail client puts it.
 */
export default async function SupportPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; thread?: string }>;
}) {
  const { status, thread } = await searchParams;
  const supabase = await createClient();

  const filter = status === "closed" ? "closed" : status === "all" ? null : "open";

  // Together, not one behind the other: admin_support_requests enforces is_support_admin() in its
  // own body, so gating on the check first only makes every real load wait a round trip for an
  // answer that is almost always yes.
  const [{ data: isSupportAdmin }, { data }] = await Promise.all([
    supabase.rpc("is_support_admin"),
    supabase.rpc("admin_support_requests", { p_status: nullableArg(filter), p_limit: 200 }),
  ]);

  if (isSupportAdmin !== true) redirect("/admin");
  const requests = (data ?? []) as SupportRequest[];

  return (
    <SupportQueue
      requests={requests}
      activeFilter={status ?? "open"}
      initialThreadId={thread}
    />
  );
}
