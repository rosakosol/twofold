// Zoho Mail's REST API, narrowed to the one thing it is needed for: fetching the attachments the
// outgoing webhook does not send.
//
// ---------------------------------------------------------------------------
// The datacenter, again
// ---------------------------------------------------------------------------
//
// `submit-help-message` already documents this trap for SMTP at length: Zoho partitions accounts by
// datacenter, each one serves only its own, and using the wrong host produces an authentication
// failure indistinguishable from a wrong password. twofoldapp.com.au is in the AU datacenter — its
// MX is mx.zoho.com.au and its SPF includes zohomail.com.au — so the defaults here are the .com.au
// hosts, and both are overridable for the day that stops being true.
//
// The symptom if they are wrong is an OAuth refusal, not a 404, which is exactly the confusing
// shape the SMTP version of this mistake takes.
//
// ---------------------------------------------------------------------------
// Refresh token in, access token out
// ---------------------------------------------------------------------------
//
// A Zoho self-client issues a refresh token once, by hand, and it does not expire. Access tokens
// last an hour. This exchanges one for the other on each sweep rather than caching: a sweep runs
// every few minutes, an exchange is one request, and a cache in an edge function whose instances
// come and go would be a source of stale-token failures for no measurable saving.

const ACCOUNTS_HOST = Deno.env.get("ZOHO_ACCOUNTS_HOST") ?? "https://accounts.zoho.com.au";
const MAIL_HOST = Deno.env.get("ZOHO_MAIL_API_HOST") ?? "https://mail.zoho.com.au";

export interface ZohoAttachment {
  attachmentId: string;
  attachmentName: string;
  attachmentSize?: number;
  contentType?: string;
}

export async function accessToken(fetchImpl: typeof fetch = fetch): Promise<string> {
  const refresh = Deno.env.get("ZOHO_REFRESH_TOKEN");
  const clientId = Deno.env.get("ZOHO_CLIENT_ID");
  const clientSecret = Deno.env.get("ZOHO_CLIENT_SECRET");
  if (!refresh || !clientId || !clientSecret) {
    throw new Error("ZOHO_REFRESH_TOKEN/ZOHO_CLIENT_ID/ZOHO_CLIENT_SECRET are not set");
  }

  const body = new URLSearchParams({
    refresh_token: refresh,
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: "refresh_token",
  });

  const response = await fetchImpl(`${ACCOUNTS_HOST}/oauth/v2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!response.ok) {
    throw new Error(`Zoho token exchange returned ${response.status}`);
  }
  const json = await response.json();
  // Zoho answers 200 with an `error` field for a bad grant, so status alone is not the check.
  if (!json.access_token) {
    throw new Error(`Zoho token exchange gave no token: ${json.error ?? "unknown"}`);
  }
  return json.access_token as string;
}

/// The account the mailbox belongs to. Distinct from the webhook's `zuid`, which identifies the
/// user rather than the account, so it is looked up rather than assumed — and can be pinned with
/// ZOHO_ACCOUNT_ID once known, to save a request per sweep.
export async function accountId(token: string, fetchImpl: typeof fetch = fetch): Promise<string> {
  const pinned = Deno.env.get("ZOHO_ACCOUNT_ID");
  if (pinned) return pinned;

  const response = await fetchImpl(`${MAIL_HOST}/api/accounts`, {
    headers: { Authorization: `Zoho-oauthtoken ${token}` },
  });
  if (!response.ok) throw new Error(`Zoho accounts returned ${response.status}`);
  const json = await response.json();
  const id = json?.data?.[0]?.accountId;
  if (!id) throw new Error("Zoho returned no account id");
  return String(id);
}

/// What a message carries. An empty list is a real answer — most mail has no attachments — and is
/// what lets the sweep settle a message as done rather than retrying it forever.
export async function attachmentInfo(
  token: string,
  account: string,
  folderId: string,
  messageId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<ZohoAttachment[]> {
  const url = `${MAIL_HOST}/api/accounts/${encodeURIComponent(account)}/folders/${
    encodeURIComponent(folderId)
  }/messages/${encodeURIComponent(messageId)}/attachmentinfo`;

  const response = await fetchImpl(url, { headers: { Authorization: `Zoho-oauthtoken ${token}` } });
  if (!response.ok) throw new Error(`Zoho attachmentinfo returned ${response.status}`);

  const json = await response.json();
  const list = json?.data?.attachments ?? json?.data ?? [];
  if (!Array.isArray(list)) return [];
  return list
    .filter((a: unknown) => a && typeof a === "object")
    // deno-lint-ignore no-explicit-any
    .map((a: any) => ({
      attachmentId: String(a.attachmentId ?? a.attachmentid ?? ""),
      attachmentName: String(a.attachmentName ?? a.attachmentname ?? "attachment"),
      attachmentSize: Number(a.attachmentSize ?? a.size ?? 0) || undefined,
      contentType: a.contentType ?? a.mimeType ?? undefined,
    }))
    .filter((a: ZohoAttachment) => a.attachmentId !== "");
}

export async function downloadAttachment(
  token: string,
  account: string,
  folderId: string,
  messageId: string,
  attachmentId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Uint8Array> {
  const url = `${MAIL_HOST}/api/accounts/${encodeURIComponent(account)}/folders/${
    encodeURIComponent(folderId)
  }/messages/${encodeURIComponent(messageId)}/attachments/${encodeURIComponent(attachmentId)}`;

  const response = await fetchImpl(url, { headers: { Authorization: `Zoho-oauthtoken ${token}` } });
  if (!response.ok) throw new Error(`Zoho attachment download returned ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

/// A key under our own prefix, built from ids we control. The sender chose the filename; they do
/// not get to choose where it lands — the same rule the outbound side follows.
export function inboundKey(requestId: string, attachmentId: string, filename: string): string {
  const ext = (filename.match(/\.([a-zA-Z0-9]{1,8})$/)?.[1] ?? "bin").toLowerCase();
  const safeId = attachmentId.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 40) || "att";
  return `support/inbound/${requestId}/${safeId}.${ext}`;
}
