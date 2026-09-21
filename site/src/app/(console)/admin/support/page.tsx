import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { nullableArg } from "@/lib/db/nullableArg";
import { SupportQueue, type SupportRequest } from "@/components/console/SupportQueue";

export const metadata: Metadata = { title: "Support" };
export const dynamic = "force-dynamic";

/**
 * The queue that did not exist until now.
 *
 * Both contact paths composed an email and kept nothing, so the 48-hour response the app promises
 * for an abuse report rested entirely on somebody reading an inbox, and there was no way to tell
 * whether a request had been answered. The email is still sent, unchanged — it is what actually
 * notifies anyone. This is the record beside it.
 */
export default async function SupportPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const supabase = await createClient();

  const { data: isSupportAdmin } = await supabase.rpc("is_support_admin");
  if (isSupportAdmin !== true) redirect("/admin");

  const filter = status === "closed" ? "closed" : status === "all" ? null : "open";

  const { data } = await supabase.rpc("admin_support_requests", {
    p_status: nullableArg(filter),
    p_limit: 200,
  });
  const requests = (data ?? []) as SupportRequest[];

  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-heading text-xl font-semibold tracking-tight">Support</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Everything sent through the app&apos;s Help screen and the website&apos;s contact form.
          Each one was also emailed to support@ — this is the record, not a replacement.
        </p>
      </header>

      <SupportQueue requests={requests} activeFilter={status ?? "open"} />
    </div>
  );
}
