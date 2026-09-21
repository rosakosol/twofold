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
import { closeQuietly, dotStuff, fromAddress, singleLine, smtpClient } from "../_shared/mail.ts";
import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";
import { replyHtml, replySubject, replyText, replyToAddress, usableAsInReplyTo } from "./compose.ts";
import { serveWithCors } from "../_shared/cors.ts";

interface Body {
  threadId?: string;
  body?: string;
  close?: boolean;
  note?: string;
  /// Ids from `reserve_support_attachment`, already uploaded to R2 by the browser.
  attachmentIds?: string[];
}

function bad(message: string, status = 400): Response {
  return Response.json({ error: message }, { status });
}

Deno.serve(serveWithCors(async (req) => {
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

  // Fetched before SMTP opens, so a missing object fails the send rather than half-sending it —
  // a reply that goes out without the screenshot it refers to is worse than one that did not go.
  //
  // Held in memory because denomailer wants the bytes; the 10MB-per-file and 5-file ceilings in
  // `reserve_support_attachment` are sized for exactly this moment rather than for the bucket.
  const attachmentIds = (input.attachmentIds ?? []).filter((id) => typeof id === "string");
  const attachments: { filename: string; contentType: string; encoding: "binary"; content: Uint8Array }[] = [];

  if (attachmentIds.length > 0) {
    const { data: files, error: filesError } = await serviceClient.rpc("support_attachments_for_send", {
      p_ids: attachmentIds,
    });
    if (filesError) {
      console.error("[send-support-reply] could not load attachments:", filesError.message);
      return bad("Couldn't read the attachments. Nothing has been sent.", 500);
    }

    for (const file of (files ?? []) as { filename: string; content_type: string; r2_key: string; thread_id: string }[]) {
      // An attachment reserved against a different conversation must not ride along on this one.
      if (file.thread_id !== input.threadId) {
        return bad("An attachment does not belong to this conversation.", 409);
      }
      try {
        const url = await presign(r2ConfigFromEnv(), file.r2_key, { method: "GET", expiresIn: 300 });
        const response = await fetch(url);
        if (!response.ok) throw new Error(`R2 returned ${response.status}`);
        attachments.push({
          filename: file.filename,
          contentType: file.content_type,
          encoding: "binary",
          content: new Uint8Array(await response.arrayBuffer()),
        });
      } catch (err) {
        console.error("[send-support-reply] could not fetch attachment:", (err as Error).message);
        return bad("Couldn't read one of the attachments. Nothing has been sent.", 502);
      }
    }
  }

  // Declared out here so `finally` can reach it: hanging up must not be able to decide whether the
  // mail was sent. `await client.close()` inside this try did exactly that — Zoho does not reliably
  // send the goodbye denomailer waits for, so close() blocked until the runtime reaped the isolate
  // and the caller got a non-2xx with no body, for a reply that had already gone out. The operator
  // then reads "Nothing has changed" and sends it again. See closeQuietly.
  let client: ReturnType<typeof smtpClient> | undefined;
  try {
    client = smtpClient();
    await client.send({
      from: sender,
      to: t.email,
      // The token comes home here. singleLine because this value reaches a header, the same
      // treatment submit-help-message already gives its subject.
      replyTo: singleLine(replyToAddress(sender, t.token)),
      subject: singleLine(replySubject(t.subject)),
      // Both halves, which makes this multipart/alternative: the client picks. A support reply
      // that arrives as bare text reads as machine-generated, and one that arrives as HTML only is
      // unreadable to anybody whose client prefers text.
      // Admin-authored, so this is not the unauthenticated case — but it is the same primitive on
      // the same transport, and an admin account is exactly what an attacker would want to reach.
      content: dotStuff(replyText(body)),
      html: replyHtml(body),
      // Present only when their message carried one — a first contact through the website form has
      // no Message-ID to answer.
      // Only when what we hold is actually a Message-ID. Zoho gives us its own numeric id, which
      // is right for the Mail API and wrong for a mail header.
      inReplyTo: usableAsInReplyTo(t.last_inbound_message_id),
      references: usableAsInReplyTo(t.last_inbound_message_id),
      attachments: attachments.length > 0 ? attachments : undefined,
    });
  } catch (err) {
    console.error("[send-support-reply] SMTP send failed:", (err as Error).message);
    // Nothing is recorded, so the conversation stays exactly as it was and the retry is clean.
    return bad("Couldn't send that reply. Nothing has changed — try again.", 502);
  } finally {
    await closeQuietly(client);
  }

  const { data: requestId, error: recordError } = await serviceClient.rpc("record_support_reply", {
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

  // Binds the files to the message that carried them, which is also what stops the nightly sweep
  // collecting them as abandoned. A failure here leaves the attachment rows dangling — the reply is
  // recorded and the files are in the bucket, so nothing the recipient sees is affected.
  if (attachmentIds.length > 0 && requestId) {
    const { error: attachError } = await serviceClient.rpc("attach_support_attachments", {
      p_ids: attachmentIds,
      p_request_id: requestId,
    });
    if (attachError) {
      console.error("[send-support-reply] sent and recorded, but attachments not bound:", attachError.message);
    }
  }

  return Response.json({ ok: true, recorded: true, attachments: attachments.length });
}));

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/send-support-reply' \
    --header 'Authorization: Bearer <support admin access token>' \
    --header 'Content-Type: application/json' \
    --data '{"threadId":"<uuid>","body":"Thanks for writing in...","close":true}'

*/
