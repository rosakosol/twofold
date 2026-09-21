// Answering a support conversation from the console.
//
// Without this the queue could be read but not answered, which left support in two places — the
// conversation here, the reply in Zoho, and no record in either of what the other had done.
//
// ---------------------------------------------------------------------------
// Send first, record second
// ---------------------------------------------------------------------------
//
// The row is written only after SMTP has accepted the message. The other order is tempting because
// it is tidier, and it is wrong: a row claiming we answered when the send failed is worse than no
// row at all, because it tells whoever reads the queue next that this is handled and the person
// waiting never hears anything.
//
// The cost of this order is the opposite failure — mail sent and not recorded, if the database is
// unreachable in the moment between. That leaves a conversation looking unanswered when it was
// answered, which produces a duplicate reply and a slightly confused customer. Of the two, only one
// leaves somebody with silence.
//
// ---------------------------------------------------------------------------
// Two threading mechanisms, doing different jobs
// ---------------------------------------------------------------------------
//
//   * Reply-To carries our token — `support+t<token>@twofoldapp.com.au`. Zoho delivers
//     plus-addressed mail to the base mailbox, so their reply comes back with the token in a field
//     the webhook already gives us. This is what threads the conversation on OUR side, and it
//     survives them rewriting the subject.
//
//   * In-Reply-To carries the Message-ID of their last message. This is what makes our reply sit
//     under theirs in THEIR mail client.
//
// Neither substitutes for the other, and a reply wants both.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { fromAddress, singleLine, smtpClient } from "../_shared/mail.ts";
import { replySubject, replyToAddress } from "./compose.ts";

interface Body {
  threadId?: string;
  body?: string;
  close?: boolean;
  note?: string;
}

function bad(message: string, status = 400): Response {
  return Response.json({ error: message }, { status });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("Method not allowed", 405);

  let input: Body;
  try {
    input = await req.json();
  } catch {
    return bad("Invalid request");
  }

  const body = (input.body ?? "").trim();
  if (!input.threadId) return bad("No conversation given.");
  if (!body) return bad("A reply cannot be empty.");
  if (body.length > 20000) return bad("That reply is too long.");

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return bad("Not authenticated", 401);

  // Asked of the database, against the caller's own JWT — never of the service client, which is an
  // admin by construction and would answer yes to anybody.
  const { data: isSupportAdmin } = await userClient.rpc("is_support_admin");
  if (isSupportAdmin !== true) return bad("Not authorised", 403);

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: thread, error: threadError } = await serviceClient.rpc("support_thread_for_reply", {
    p_thread_id: input.threadId,
  });
  if (threadError || !thread) {
    console.error("[send-support-reply] could not load thread:", threadError?.message);
    return bad("That conversation could not be found.", 404);
  }

  // deno-lint-ignore no-explicit-any
  const t = thread as any;
  if (!t.email) return bad("That conversation has no address to reply to.", 409);

  const sender = fromAddress();
  if (!sender) {
    console.error("[send-support-reply] ZOHO_FROM_ADDRESS/ZOHO_SMTP_USER is not configured");
    return bad("Email sending isn't set up.", 503);
  }

  try {
    const client = smtpClient();
    await client.send({
      from: sender,
      to: t.email,
      // The token comes home here. singleLine because this value reaches a header, the same
      // treatment submit-help-message already gives its subject.
      replyTo: singleLine(replyToAddress(sender, t.token)),
      subject: singleLine(replySubject(t.subject)),
      content: body,
      // Present only when their message carried one — a first contact through the website form has
      // no Message-ID to answer.
      inReplyTo: t.last_inbound_message_id ?? undefined,
      references: t.last_inbound_message_id ?? undefined,
    });
    await client.close();
  } catch (err) {
    console.error("[send-support-reply] SMTP send failed:", (err as Error).message);
    // Nothing is recorded, so the conversation stays exactly as it was and the retry is clean.
    return bad("Couldn't send that reply. Nothing has changed — try again.", 502);
  }

  const { error: recordError } = await serviceClient.rpc("record_support_reply", {
    p_thread_id: input.threadId,
    p_actor: user.id,
    p_body: body,
    p_close: input.close !== false,
    p_note: (input.note ?? "").trim() || null,
  });

  if (recordError) {
    // The mail HAS gone. Saying "it failed" would invite a second one, so this reports success and
    // says the record is missing — the honest description of what happened.
    console.error("[send-support-reply] sent but could not record:", recordError.message);
    return Response.json({
      ok: true,
      recorded: false,
      warning: "The reply was sent, but the conversation could not be updated. Do not resend.",
    });
  }

  return Response.json({ ok: true, recorded: true });
});

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/send-support-reply' \
    --header 'Authorization: Bearer <support admin access token>' \
    --header 'Content-Type: application/json' \
    --data '{"threadId":"<uuid>","body":"Thanks for writing in...","close":true}'

*/
