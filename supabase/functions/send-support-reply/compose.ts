// How a reply is addressed and titled. Pure, so it can be tested without SMTP — index.ts calls
// Deno.serve at import time, the same reason revenuecat-webhook/subscriber.ts exists.

/// `support@twofoldapp.com.au` + a token -> `support+t<token>@twofoldapp.com.au`.
///
/// Built from the sending address rather than hardcoded, so it follows ZOHO_FROM_ADDRESS if that
/// ever changes and cannot quietly point at a mailbox nobody reads.
export function replyToAddress(sender: string, token: string): string {
  const at = sender.lastIndexOf("@");
  if (at < 0 || !token) return sender;
  return `${sender.slice(0, at)}+t${token}${sender.slice(at)}`;
}

/// "Cannot sign in" -> "Re: Cannot sign in", and "Re: Cannot sign in" -> itself.
///
/// Stacking prefixes is what produces "Re: Re: Fwd: Re:" after a few exchanges. Our own thread key
/// strips them on the way in, so this is cosmetic on our side — but it is what the correspondent
/// reads, and a subject that grows a prefix per message looks like a machine talking.
export function replySubject(subject: string | null | undefined): string {
  const trimmed = (subject ?? "").trim();
  if (!trimmed) return "Re: your message to Twofold support";
  return /^re\s*(\[[0-9]+\])?\s*:/i.test(trimmed) ? trimmed : `Re: ${trimmed}`;
}
