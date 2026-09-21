import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

/**
 * The account portal: what someone can do about their own account without emailing anyone.
 *
 * It lives in the (board) group, under the website's own header and footer, rather than in its own
 * shell like the console. That is deliberate — the console is an internal tool a customer should
 * never see, while this is an ordinary part of the website for the person whose account it is, and
 * they should be able to get back to Pricing or the FAQ from it without losing their place.
 *
 * Redirects to sign-in carrying `next`, so arriving here from an email or a bookmark lands on the
 * account page after signing in rather than on the feedback board.
 */
export default async function AccountLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) redirect("/auth/sign-in?next=/account");

  return <div className="mx-auto max-w-2xl px-4 py-10">{children}</div>;
}
