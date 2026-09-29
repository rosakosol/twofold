/**
 * A port of `PasswordPolicy` from the iOS app (Twofold/Twofold/Shared/PasswordPolicy.swift).
 *
 * Kept in sync by hand — there is no codegen between Swift and TypeScript, the same acceptance this
 * repo already makes for FlightStatus, the support categories and the web stores. What has to match
 * is the two lists and the thresholds: a password this file accepts and the app refuses is an
 * account somebody can create here and then cannot change their password on, and one it refuses
 * that the app accepts is a person locked out of buying for no stated reason.
 *
 * The rule this replaced was a length test in disguise — its last tier returned "fair" for anything
 * eight characters long, and every gate reads "better than weak", so "password", "12345678" and
 * "aaaaaaaa" all passed. See the Swift file's header for the full account.
 */
export type PasswordStrength = "weak" | "fair" | "strong";

const RANK: Record<PasswordStrength, number> = { weak: 0, fair: 1, strong: 2 };

export const MIN_PASSWORD_LENGTH = 10;
/** Where "fair" becomes "strong". Not a gate — everything below still passes every rule. */
const STRONG_LENGTH = 14;

/** Mirrors `PasswordPolicy.commonPasswords`, same entries, same order. */
const COMMON_PASSWORDS = new Set([
  "password", "passw0rd", "pass", "qwerty", "qwertyuiop", "asdfgh", "zxcvbn",
  "iloveyou", "princess", "sunshine", "football", "baseball", "superman", "batman",
  "dragon", "monkey", "master", "shadow", "michael", "jennifer", "jordan",
  "letmein", "welcome", "admin", "login", "abc", "trustno", "starwars",
  "whatever", "freedom", "hello", "charlie", "donald", "qazwsx", "soccer",
  "killer", "ninja", "mustang", "access", "flower", "hottie", "loveme",
  "zaq", "google", "chocolate", "computer", "internet", "samsung", "cheese",
  "twofold", "relationship", "boyfriend", "girlfriend", "longdistance",
]);

export function varietyCount(password: string): number {
  let count = 0;
  if (/\p{Lu}/u.test(password)) count += 1;
  if (/\p{Ll}/u.test(password)) count += 1;
  if (/\p{Nd}/u.test(password)) count += 1;
  if (/[^\p{L}\p{N}]/u.test(password)) count += 1;
  return count;
}

/**
 * Trailing digits and symbols stripped before the lookup — "password1" and "Password1!" are not new
 * ideas. The symbol half matters because a capital, a number and a symbol are all required now, and
 * the shortest route from a banned password to a compliant one is to bolt one of each onto the end.
 */
export function isCommonPassword(password: string): boolean {
  const lowered = password.toLowerCase();
  if (COMMON_PASSWORDS.has(lowered)) return true;
  const stem = lowered.replace(/[^\p{L}]+$/u, "");
  return stem !== "" && COMMON_PASSWORDS.has(stem);
}

/**
 * The whole password is one shorter string repeated — "passwordpassword", "abcabcabc". Returns the
 * unit, or null if there isn't one.
 *
 * Repetition satisfies a length floor and a whole-string blocklist at the same time, which is what
 * somebody reaches for when told their password is too short. Checked against the blocklist and a
 * minimum unit length rather than banned outright: "tangerinetangerine" repeats and is fine.
 */
export function repeatedUnit(password: string): string | null {
  const characters = [...password];
  const length = characters.length;
  if (length < 4) return null;

  for (let unit = 1; unit <= Math.floor(length / 2); unit += 1) {
    if (length % unit !== 0) continue;
    const candidate = characters.slice(0, unit).join("");
    let matches = true;
    for (let index = unit; index < length; index += unit) {
      if (characters.slice(index, index + unit).join("") !== candidate) {
        matches = false;
        break;
      }
    }
    if (matches) return candidate;
  }
  return null;
}

/** Four or more identical characters, or four or more running consecutively either way. */
export function hasTrivialRun(password: string): boolean {
  const codes = [...password.toLowerCase()].map((character) => character.codePointAt(0) ?? 0);
  if (codes.length < 4) return false;

  let repeat = 1;
  let ascending = 1;
  let descending = 1;
  for (let index = 1; index < codes.length; index += 1) {
    const delta = codes[index] - codes[index - 1];
    repeat = delta === 0 ? repeat + 1 : 1;
    ascending = delta === 1 ? ascending + 1 : 1;
    descending = delta === -1 ? descending + 1 : 1;
    if (repeat >= 4 || ascending >= 4 || descending >= 4) return true;
  }
  return false;
}

function fold(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/\s/gu, "");
}

/**
 * The password contains the person's own name, or their email's local part. Four characters minimum
 * on the needle, so somebody called "Al" is not told their password contains their name.
 */
export function containsPersonalInformation(password: string, name?: string, email?: string): boolean {
  const haystack = fold(password);
  const needles: string[] = [];
  if (name) needles.push(fold(name));
  if (email) needles.push(fold(email.split("@")[0] ?? email));
  return needles.some((needle) => needle.length >= 4 && haystack.includes(needle));
}

/**
 * Why the password was refused, phrased for the person typing it — nil when it passes.
 *
 * A disabled button with no reason is its own dead end, and a stricter rule makes more of them.
 */
export function passwordRejectionReason(password: string, name?: string, email?: string): string | null {
  if ([...password].length < MIN_PASSWORD_LENGTH) {
    return `Use at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (containsPersonalInformation(password, name, email)) {
    return "Don't use your name or email address in your password.";
  }
  if (isCommonPassword(password)) {
    return "That's a commonly used password — please pick something less guessable.";
  }
  const unit = repeatedUnit(password);
  if (unit !== null && ([...unit].length < 4 || isCommonPassword(unit))) {
    return "Repeating a word doesn't make it a stronger password.";
  }
  if (hasTrivialRun(password)) {
    return 'Avoid repeated or sequential characters like "aaaa" or "1234".';
  }
  if (!/\p{Lu}/u.test(password)) return "Add a capital letter.";
  if (!/\p{Ll}/u.test(password)) return "Add a lowercase letter.";
  if (!/\p{Nd}/u.test(password)) return "Add a number.";
  if (!/[^\p{L}\p{N}]/u.test(password)) return "Add a special character, like ! or ?";
  return null;
}

export function evaluatePassword(password: string, name?: string, email?: string): PasswordStrength {
  if (passwordRejectionReason(password, name, email) !== null) return "weak";
  // Everything reaching here already carries all four classes, so length is all that's left.
  return [...password].length >= STRONG_LENGTH ? "strong" : "fair";
}

/** The gate the button uses. */
export function isAcceptablePassword(password: string, name?: string, email?: string): boolean {
  return RANK[evaluatePassword(password, name, email)] > RANK.weak;
}

export function passwordStrengthLabel(password: string, name?: string, email?: string): string {
  switch (evaluatePassword(password, name, email)) {
    case "strong":
      return "Strong";
    case "fair":
      return "Fair";
    default:
      return "Weak";
  }
}
