import type { ReactNode } from "react";

/*
 * An FAQ answer, formatted the way the website spec asks (docs/TWOFOLD_WEBSITE.md, section 7)
 * without changing a word of it: paragraphs at its own line breaks, " - " as an en dash, settings
 * paths ("Settings → Help → Export your data") and site paths ("twofoldapp.com.au/account") in
 * semibold, and the support address as a link. The answers are the live copy from faq_entries,
 * shared with the app, so this only presents them.
 */

const SUPPORT_EMAIL = /([\w.+-]+@twofoldapp\.com\.au)/;
// A path: a capitalised first step ("Settings", "Apple Account"), then one or more "→ step"
// segments, each running to punctuation or a joining word. Or a path on the site.
const PATH = /([A-Z][\w']*(?: [A-Z][\w']*)*(?: → [\w'][\w' ]*?)+(?=[.,;:!?)]|$| (?:and|or|then|to|in|on|if|from|under|where|is|you)\b)|twofoldapp\.com\.au\/[\w/-]+)/;

function inline(text: string, keyBase: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  const pattern = new RegExp(`${SUPPORT_EMAIL.source}|${PATH.source}`, "g");
  let last = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text))) {
    if (match.index > last) nodes.push(text.slice(last, match.index));
    const [whole, email] = match;
    nodes.push(
      email ? (
        <a key={`${keyBase}-${match.index}`} href={`mailto:${email}`}>
          {email}
        </a>
      ) : (
        <strong key={`${keyBase}-${match.index}`}>{whole}</strong>
      )
    );
    last = match.index + whole.length;
  }
  if (last < text.length) nodes.push(text.slice(last));
  return nodes;
}

/** A long answer with no line breaks of its own, cut into paragraphs of a few sentences. Only
 *  ever between sentences, so not a word changes; short answers stay one paragraph. */
function paragraphsOf(text: string): string[] {
  const written = text.split(/\n\s*\n|\n/).map((p) => p.trim()).filter(Boolean);
  if (written.length > 1 || text.length <= 320) return written;
  const sentences = text.split(/(?<=[.!?])\s+(?=[A-Z])/);
  const out: string[] = [];
  let current = "";
  for (const sentence of sentences) {
    if (current && current.length + sentence.length > 300) {
      out.push(current);
      current = sentence;
    } else {
      current = current ? `${current} ${sentence}` : sentence;
    }
  }
  if (current) out.push(current);
  return out;
}

export function formatFaqAnswer(answer: string): ReactNode {
  return paragraphsOf(answer.replace(/ - /g, " – ")).map((paragraph, i) => (
    <p key={i}>{inline(paragraph, String(i))}</p>
  ));
}

/** A category from faq_entries as the spec names the groups: sentence case, "and" for "&". The
 *  column itself is shared with the app and stays as it is. */
export function faqGroupLabel(category: string): string {
  const label = category.replace(/\s*&\s*/g, " and ");
  return label.charAt(0).toUpperCase() + label.slice(1).toLowerCase();
}
