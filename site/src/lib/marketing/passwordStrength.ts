/**
 * A port of `PasswordStrength` from the iOS app
 * (Twofold/Twofold/DesignSystem/Components/PasswordStrength.swift).
 *
 * Kept in sync by hand, the same way this repo already accepts for FlightStatus, the support
 * categories and the web stores — there is no codegen between Swift and TypeScript. The thresholds
 * below are the ones that matter: `CreateAccountView` and `SaveAccountView` both gate signup on
 * `evaluate(password) > .weak`, so anything this file judges differently is an account the app
 * would have refused to create, or one it would have allowed and the website did not.
 *
 * Unicode property escapes rather than `[A-Z]` and friends, because Swift's `CharacterSet
 * .uppercaseLetters` is Unicode-aware and an ASCII class here would quietly rate "Ünïcödé" as
 * having no uppercase.
 */
export type PasswordStrength = "weak" | "fair" | "strong";

const RANK: Record<PasswordStrength, number> = { weak: 0, fair: 1, strong: 2 };

export function evaluatePassword(password: string): PasswordStrength {
  // `.length` counts UTF-16 units where Swift's `count` counts grapheme clusters, so an emoji
  // password is measured slightly differently here. It only ever reads longer, never shorter, so
  // the disagreement cannot let through something the app would reject on length.
  const length = password.length;

  let variety = 0;
  if (/\p{Lu}/u.test(password)) variety += 1;
  if (/\p{Ll}/u.test(password)) variety += 1;
  if (/\p{Nd}/u.test(password)) variety += 1;
  if (/[^\p{L}\p{N}]/u.test(password)) variety += 1;

  if (length >= 12 && variety >= 3) return "strong";
  if (length >= 10 && variety >= 2) return "strong";
  if (length >= 8 && variety >= 2) return "fair";
  if (length >= 8) return "fair";
  return "weak";
}

/**
 * The signup gate itself — `> .weak` in both of the app's account screens.
 *
 * Note what that actually means: the last rule above makes any password of 8 characters "fair"
 * regardless of variety, so this is a length test in everything but name, and the app's separate
 * `password.count >= 6` check can never fail on its own. Both are kept anyway, because the point is
 * to match the app rather than to be the smallest expression of it — if the thresholds there are
 * ever tightened, this file should need the same edit and not a rethink.
 */
export function isStrongEnough(password: string): boolean {
  return RANK[evaluatePassword(password)] > RANK.weak;
}

export function passwordStrengthLabel(password: string): string {
  switch (evaluatePassword(password)) {
    case "strong":
      return "Strong";
    case "fair":
      return "Fair";
    default:
      return "Weak";
  }
}
