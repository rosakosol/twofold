import fs from "node:fs";
import path from "node:path";

const templatesDir = path.join(process.cwd(), "src", "lib", "mail", "templates");

/** Loads one of the .html files in templates/ and replaces every {{token}} with the given
 * value — verbatim, no escaping done here. Callers must pre-escape any user-supplied value
 * themselves (see escapeHtml.ts) before passing it in; this function only substitutes, so it
 * never double-escapes a value a caller already prepared. Warns (doesn't throw) on an unknown
 * token, so a template edited without updating its caller fails loudly in logs rather than
 * silently shipping a broken email. */
export function renderTemplate(fileName: string, tokens: Record<string, string>): string {
  const raw = fs.readFileSync(path.join(templatesDir, `${fileName}.html`), "utf-8");
  return raw.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (match, key: string) => {
    if (!(key in tokens)) {
      console.warn(`[renderTemplate] ${fileName}.html: no value provided for {{${key}}}`);
      return match;
    }
    return tokens[key];
  });
}

/** Extracts the <title> tag's contents — every template sets {{subject}} there too, so this
 * doubles as the email's subject line once tokens are substituted (call renderTemplate first,
 * then this, so {{subject}} itself is already filled in). */
export function extractSubject(renderedHtml: string): string {
  const match = renderedHtml.match(/<title>([^<]*)<\/title>/);
  return match?.[1]?.trim() ?? "";
}
