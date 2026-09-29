/**
 * A port of `NameValidator` from the iOS app (Twofold/Twofold/Shared/NameValidator.swift).
 *
 * Same hand-sync caveat as passwordStrength.ts. The app applies these at submit time in
 * `CreateAccountView` and `PartnerNameView`; /pricing now creates accounts too, and a name the app
 * would refuse must not arrive through the website instead.
 */

export const MIN_NAME_LENGTH = 2;

/** Letters plus the punctuation real names use — no digits, no other symbols. */
const ALLOWED_NAME = /^[\p{L} '\-]+$/u;

/**
 * Blocked wherever they appear, even inside a longer word. Only terms that never occur inside real
 * names belong here — shorter or ambiguous ones go in BANNED_WORDS to avoid Scunthorpe-style false
 * positives ("Kikelomo" contains "kike", "Analise" contains "anal").
 */
const BANNED_SUBSTRINGS = [
  "fuck", "shit", "bitch", "cunt", "whore", "slut", "wank", "twat",
  "nigg", "faggot", "retard", "dildo", "penis", "vagina", "hitler",
];

/** Blocked only as a standalone word, because they appear inside real names ("Cassandra", "Cockburn"). */
const BANNED_WORDS = new Set([
  "ass", "arse", "dick", "cock", "tits", "hoe", "fag", "prick",
  "nazi", "kike", "spic", "chink", "coon", "cum", "sex", "porn",
]);

/** A user-facing error, or null if the name passes the structural checks. */
export function nameStructuralError(rawName: string): string | null {
  const name = rawName.trim();
  if ([...name].length < MIN_NAME_LENGTH) return `Enter at least ${MIN_NAME_LENGTH} characters.`;
  if (!ALLOWED_NAME.test(name)) return "Names can only contain letters.";
  return null;
}

/** Fold case and diacritics, so "FÜCK" still matches "fuck". */
function fold(value: string): string {
  return value.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
}

export function isInappropriateName(rawName: string): boolean {
  const folded = fold(rawName);

  const words = folded.split(/[ '\-]+/u).filter(Boolean);
  if (words.some((word) => BANNED_WORDS.has(word))) return true;

  // Squash separators so "f u c k" and "f-u-c-k" cannot dodge the substring check.
  const squashed = folded.replace(/[ '\-]/gu, "");
  return BANNED_SUBSTRINGS.some((banned) => squashed.includes(banned));
}

/** Everything the app checks, in one call. Null when the name is fine. */
export function nameError(rawName: string): string | null {
  const structural = nameStructuralError(rawName);
  if (structural) return structural;
  if (isInappropriateName(rawName)) return "Please use your real first name.";
  return null;
}
