import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/db/types";

const LISTS = new Set(["product_news", "feedback_updates", "android_waitlist", "all"]);

/**
 * One-click unsubscribe (RFC 8058): what a mail app's own Unsubscribe button calls, from the
 * List-Unsubscribe header on our emails. A POST, which link scanners do not make, so it can act
 * at once. The token in the link is the only credential, and it changes only its own address.
 *
 * People who click the link in the email body land on /unsubscribe instead, which asks first.
 */
export async function POST(request: Request) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") ?? "";
  const list = url.searchParams.get("list") ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(token) || !LISTS.has(list)) {
    return NextResponse.json({ error: "Invalid link." }, { status: 400 });
  }

  const supabase = createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
  const { data, error } = await supabase.rpc("set_email_preference_by_token", {
    p_token: token,
    p_list: list,
    p_enabled: false,
  });
  if (error) {
    return NextResponse.json({ error: "Something went wrong. Please try again." }, { status: 500 });
  }
  if (data === false) {
    return NextResponse.json({ error: "This link isn't valid any more." }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
