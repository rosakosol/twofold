// Collects the attachments Zoho's webhook leaves behind.
//
// The webhook carries no attachments at all, only the handles to ask about them. `ingest-support-email`
// marks each emailed message `pending`; this sweep asks Zoho what it carried, puts anything it finds
// in R2, and settles the state.
//
// A sweep rather than inline work in the webhook, because fetching means an OAuth exchange, a
// metadata call, and a download plus an upload per file. Zoho's answer to a webhook that takes that
// long is to retry it, and eventually to disable it. Here every failure is retried for free
// instead: a message stays `pending` until it genuinely resolves, so an outage delays attachments
// rather than losing them.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";
import { accessToken, accountId, attachmentInfo, downloadAttachment, inboundKey, inboxFolderId } from "../_shared/zoho-api.ts";

/// Matches the outbound ceiling. A support mailbox receives the occasional video, and pulling one
/// into an edge function's memory to move it is how the sweep dies mid-run and leaves a message
/// half-collected.
const MAX_BYTES = 10 * 1024 * 1024;

interface Pending {
  id: string;
  thread_id: string;
  message_id: string;
  folder_id: string | null;
  zoho_account_id: string | null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await serviceClient.rpc("support_messages_awaiting_attachments", {
    p_limit: 20,
  });
  if (error) {
    console.error("[fetch-support-attachments] could not list pending:", error.message);
    return Response.json({ error: "Could not list" }, { status: 500 });
  }

  const pending = (data ?? []) as Pending[];
  if (pending.length === 0) return Response.json({ ok: true, checked: 0 });

  let token: string;
  let account: string;
  let inbox: string;
  try {
    token = await accessToken();
    account = await accountId(token);
    // Looked up once per sweep rather than taken from each message: the webhook does not send
    // folderId, so relying on it meant every message was unaskable.
    inbox = await inboxFolderId(token, account);
  } catch (err) {
    // Left pending deliberately. This is a configuration or an outage, not a property of any
    // message, so the next run should try all of them again rather than marking them failed.
    console.error("[fetch-support-attachments] Zoho auth failed:", (err as Error).message);
    return Response.json({ error: "Zoho auth failed", pending: pending.length }, { status: 503 });
  }

  const r2 = r2ConfigFromEnv();
  let checked = 0;
  let stored = 0;

  for (const message of pending) {
    // The message's own folder id when the webhook happened to send one, otherwise the Inbox —
    // which in practice is always, since production shows folderId arriving null every time.
    const folder = message.folder_id || inbox;

    try {
      const info = await attachmentInfo(token, message.zoho_account_id || account, folder, message.message_id);
      const saved: Record<string, unknown>[] = [];

      for (const attachment of info) {
        if ((attachment.attachmentSize ?? 0) > MAX_BYTES) {
          // Recorded as absent rather than silently dropped would be worse than either: the log
          // line is what tells somebody why a screenshot they were told about is not here.
          console.warn(
            `[fetch-support-attachments] skipping ${attachment.attachmentName} on ${message.message_id}: ` +
              `${attachment.attachmentSize} bytes exceeds the ${MAX_BYTES} ceiling`,
          );
          continue;
        }

        const bytes = await downloadAttachment(
          token, message.zoho_account_id || account, folder, message.message_id, attachment.attachmentId,
        );
        const contentType = attachment.contentType || "application/octet-stream";
        const key = inboundKey(message.id, attachment.attachmentId, attachment.attachmentName);

        const uploadUrl = await presign(r2, key, { method: "PUT", expiresIn: 300, contentType });
        const put = await fetch(uploadUrl, {
          method: "PUT",
          headers: { "Content-Type": contentType },
          body: bytes,
        });
        if (!put.ok) throw new Error(`R2 PUT returned ${put.status}`);

        saved.push({
          filename: attachment.attachmentName,
          content_type: contentType,
          size_bytes: bytes.byteLength,
          r2_key: key,
        });
      }

      // One call, so a message can never be marked done with its attachments half-written. The keys
      // are unique, so a re-run after a partial failure re-uploads to the same place and inserts
      // nothing twice.
      await serviceClient.rpc("record_inbound_attachments", {
        p_request_id: message.id,
        p_attachments: saved,
        p_state: "done",
      });
      checked++;
      stored += saved.length;
    } catch (err) {
      // Left pending on purpose: the usual cause is Zoho being briefly unavailable, and the next
      // sweep is a free retry. Only a message that keeps failing needs a human, and the log is
      // where that becomes visible.
      console.error(
        `[fetch-support-attachments] ${message.message_id} failed:`,
        (err as Error).message,
      );
    }
  }

  return Response.json({ ok: true, checked, stored, pending: pending.length });
});
