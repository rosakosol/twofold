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

/// Escapes text for HTML. The reply is typed by an admin rather than a stranger, so this is not a
/// defence against an attacker — it is a defence against a person writing `<` or `&` in a sentence
/// and silently losing the rest of their paragraph to a browser's error recovery.
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// Bare URLs become links, because a support reply's whole job is often to hand somebody a link and
/// a URL that has to be copied out of an email is one people get wrong.
///
/// Deliberately narrow: http(s) only, stopping at whitespace, and trimming trailing punctuation so
/// "see https://example.com/help." does not produce a link ending in a full stop. Anything cleverer
/// starts linkifying things that are not links.
function linkify(escaped: string): string {
  return escaped.replace(/(https?:\/\/[^\s<]+)/g, (match) => {
    const trailing = match.match(/[.,;:!?)]+$/);
    const url = trailing ? match.slice(0, -trailing[0].length) : match;
    const tail = trailing ? trailing[0] : "";
    return `<a href="${url}" style="color:#2A6FA8;">${url}</a>${tail}`;
  });
}

/// The plain-text half. Sent alongside the HTML so a client that prefers text, or a person who
/// reads mail as text, gets something written for them rather than a tag soup fallback.
export function replyText(body: string): string {
  return `${body.trim()}\n\n—\nTwofold Support\nReply to this email and it will reach us.`;
}

/// The HTML half.
///
/// Deliberately plain: a support reply is a person answering a question, and wrapping it in a
/// branded template makes it read as marketing — which is both wrong in tone and likelier to be
/// filtered. One font stack, one colour, generous line height, and a quiet footer.
///
/// Inline styles only, and no stylesheet: mail clients strip `<style>` blocks unpredictably, which
/// is the same reason the site's own templates in lib/mail/templates are written that way.
export function replyHtml(body: string): string {
  const paragraphs = body
    .trim()
    .split(/\n{2,}/)
    .map((block) => `<p style="margin:0 0 16px;">${linkify(escapeHtml(block)).replace(/\n/g, "<br>")}</p>`)
    .join("");

  return `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;` +
    `font-size:16px;line-height:26px;color:#1C2A38;max-width:560px;">` +
    paragraphs +
    `<p style="margin:24px 0 0;font-size:14px;line-height:22px;color:#5B6B7A;">` +
    `&mdash;<br>Twofold Support<br>` +
    `<span style="color:#5B6B7A;">Reply to this email and it will reach us.</span></p></div>`;
}
