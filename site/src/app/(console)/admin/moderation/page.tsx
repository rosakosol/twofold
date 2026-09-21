import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Moderation" };
export const dynamic = "force-dynamic";

interface MostBlocked {
  profile_id: string;
  email: string | null;
  first_name: string;
  blocked_by_count: number;
  most_recent: string;
}

/**
 * Accounts that several unrelated people have blocked.
 *
 * Deliberately a ranking with a floor of two, not a browsable list of every block. One block is a
 * falling-out; several from unrelated people is the thing that turns one person's abuse report
 * into something with corroboration. A list of who blocked whom would be a graph of interpersonal
 * dislike across the whole app, answering no support question and sitting somewhere it could be
 * read for no reason.
 *
 * Blocking is invisible to the blocked party in the app — DisconnectPartnerView says "They aren't
 * told" — and nothing here changes that. This page is for looking into a report that has already
 * arrived, not for acting on people who have no idea they are on a list.
 */
export default async function ModerationPage() {
  const supabase = await createClient();

  const { data: isSupportAdmin } = await supabase.rpc("is_support_admin");
  if (isSupportAdmin !== true) redirect("/admin");

  const { data } = await supabase.rpc("admin_most_blocked", { p_min_blocks: 2, p_limit: 50 });
  const rows = (data ?? []) as MostBlocked[];

  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-heading text-xl font-semibold tracking-tight">Moderation</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Accounts blocked by more than one person.
        </p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Repeatedly blocked</CardTitle>
          <CardDescription>
            A single block is usually a break-up. Two or more unrelated ones is worth a look.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          {rows.length === 0 ? (
            <p className="px-6 pb-6 text-sm text-muted-foreground">
              Nobody has been blocked by more than one person. That is the expected state.
            </p>
          ) : (
            <ul className="divide-y">
              {rows.map((row) => (
                <li key={row.profile_id}>
                  <Link
                    href={`/admin/users/${row.profile_id}`}
                    className="flex items-center justify-between gap-4 px-6 py-3 transition-colors hover:bg-accent"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{row.email ?? "no email"}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {row.first_name || "no name"} · most recent{" "}
                        {new Date(row.most_recent).toLocaleDateString()}
                      </p>
                    </div>
                    <Badge variant={row.blocked_by_count >= 3 ? "destructive" : "secondary"}>
                      blocked by {row.blocked_by_count}
                    </Badge>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Abuse reports</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          <p>
            Reports are not in this database. The app&apos;s &ldquo;Report Abuse&rdquo; category and
            the website&apos;s support form both go through <code>submit-help-message</code>, which
            emails <code>support@twofoldapp.com.au</code> and stores nothing.
          </p>
          <p className="mt-2">
            So there is no queue to show here, and the 48-hour response the app promises rests on
            somebody reading that inbox. Capturing those submissions as rows would give this page a
            real report list — and would be its own piece of work, not a view over something that
            already exists.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
