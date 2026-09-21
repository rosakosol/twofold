// Zoho SMTP, for the functions that have to send mail to a person rather than push a
// notification to a device.
//
// `submit-help-message` has its own copy of this, deliberately left where it is. It is the only
// in-app support channel and the only way an abuse report reaches a human, and consolidating it
// into a shared module in the same change that adds an account-deletion job would put the support
// path at risk for a saving of fifteen lines. If a third caller ever appears, dedupe then.

import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

/// Throws rather than returning null when the mailbox isn't configured. A dormancy warning that
/// silently fails to send is worse than a job that fails loudly: the deletion clock keeps running
/// either way, and the whole point of the warning is that somebody gets told before their archive
/// goes.
export function smtpClient(): SMTPClient {
  const username = Deno.env.get("ZOHO_SMTP_USER");
  const password = Deno.env.get("ZOHO_SMTP_PASSWORD");
  if (!username || !password) {
    throw new Error("Zoho SMTP credentials are not configured (ZOHO_SMTP_USER/ZOHO_SMTP_PASSWORD)");
  }
  const hostname = Deno.env.get("ZOHO_SMTP_HOST") ?? "smtp.zoho.com.au";
  const port = Number(Deno.env.get("ZOHO_SMTP_PORT") ?? "465");
  return new SMTPClient({
    connection: { hostname, port, tls: port === 465, auth: { username, password } },
  });
}

/// Dot-stuffs a plain-text mail body, which the transport does not do for us.
///
/// SMTP ends the DATA section at a line containing a single "." — so any body holding
/// `\r\n.\r\n` terminates the message early and everything after it is read as SMTP commands, on
/// a session already authenticated as us. The result is arbitrary mail from our own domain,
/// SPF- and DKIM-aligned, to any recipient: a phishing relay rather than a data leak.
///
/// denomailer 1.6.0 writes the body straight out and appends its own ".\r\n" with no stuffing
/// anywhere, and the quoted-printable pass does not help — "." is code 46 and sits in the
/// printable passthrough range, as do CR and LF.
///
/// Stuffing is the right fix rather than stripping: the receiving server removes the extra dot, so
/// what a human reads is unchanged, and no line a caller writes can ever be a lone ".". Every
/// body that contains anything a person typed should go through this — which is all three of them:
/// a support message, a support reply, and a dormancy warning that opens with the recipient's own
/// `first_name`, a column with no validation on it at all.
export function dotStuff(text: string): string {
  return text
    .split(/\r?\n/)
    .map((line) => (line.startsWith(".") ? `.${line}` : line))
    .join("\n");
}

export function fromAddress(): string {
  return Deno.env.get("ZOHO_FROM_ADDRESS") ?? Deno.env.get("ZOHO_SMTP_USER")!;
}

/// Collapses anything that could forge an SMTP header. Names come from user input and reach the
/// `Subject:` line and the body; a newline in one must not be able to invent a header or a line of
/// our own formatting. Same rule `submit-help-message.singleLine` applies, and for the same reason.
export function singleLine(value: string): string {
  return value.replace(/[\r\n]+/g, " ").trim();
}

/// Hanging up, without letting the hang-up decide whether the mail was sent.
///
/// denomailer holds the TCP connection open otherwise, which keeps the isolate alive until it is
/// forcibly reaped. Two hazards make this more delicate than `await client.close()` looks, and
/// `submit-help-message` paid for both before this helper existed:
///
///   * `close()` returns undefined rather than a promise when the connection never came up — an
///     auth failure, say — so it cannot be treated as a promise unconditionally.
///   * when the connection *did* come up it can block indefinitely, waiting on a server goodbye
///     Zoho does not reliably send. That stalls the request until the runtime kills it, and the
///     caller sees a non-2xx with no error body.
///
/// Either one, inside the same `try` as the send, reports a failure for a message that has already
/// gone out — which is the worst answer available, because the operator resends it. So: normalise
/// to a promise, swallow rejections, and cap the wait. Leaking the socket for the isolate's
/// remaining lifetime is much cheaper than misreporting a successful send.
export async function closeQuietly(client: SMTPClient | undefined | null): Promise<void> {
  if (!client) return;
  await Promise.race([
    Promise.resolve(client.close()).catch(() => {}),
    new Promise((resolve) => setTimeout(resolve, 2000)),
  ]);
}
