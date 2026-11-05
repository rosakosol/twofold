/**
 * The parts of TOTP enrolment and challenge that are decisions rather than calls. Copy follows the
 * house style: plain hyphens.
 */

/** Digits only, at most six, so a pasted "123 456" just works. */
export function normaliseTotpCode(raw: string): string {
  return raw.replace(/\D/g, "").slice(0, 6);
}

/**
 * The QR code as an `<img src>`. Supabase returns the SVG's markup, and auth-js prefixes it with
 * `data:image/svg+xml;utf-8,` without encoding it, so a `#` in the markup (a fill colour, say) would
 * end the URL there. Encoded here so the image doesn't depend on what the markup happens to contain.
 * No third party sees the secret: this is a local data URI, which `img-src` already allows.
 */
export function totpQrImageSrc(qrCode: string): string {
  const svg = qrCode.replace(/^data:image\/svg\+xml[^,]*,/, "");
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

/** A name for a new factor, which Supabase requires to be unique per user. */
export function nextFactorName(existing: readonly (string | null | undefined)[]): string {
  const taken = new Set(existing);
  if (!taken.has("Authenticator")) return "Authenticator";
  if (!taken.has("Backup")) return "Backup";
  for (let n = 2; ; n++) {
    if (!taken.has(`Backup ${n}`)) return `Backup ${n}`;
  }
}

/** Reads an auth error for a person. Anything unrecognised gets `fallback`, not Supabase's wording. */
export function describeMfaError(error: { code?: string; status?: number } | null | undefined, fallback: string): string {
  switch (error?.code) {
    case "mfa_verification_failed":
      return "That code didn't match. Wait for a new one in your authenticator app and try again.";
    case "mfa_challenge_expired":
      return "That took too long. Enter the current code and try again.";
    case "mfa_totp_enroll_not_enabled":
    case "mfa_totp_verify_not_enabled":
      return "Authenticator apps are switched off for this project. Turn on TOTP in Supabase: Authentication, then Multi-Factor.";
    case "insufficient_aal":
      return "Enter a code from your authenticator first. Sign out and back in if this keeps happening.";
    case "too_many_enrolled_mfa_factors":
      return "This account has as many authenticators as it can hold. Remove one first.";
    case "over_request_rate_limit":
      return "Too many tries. Wait a few minutes and try again.";
    default:
      return error?.status === 429 ? "Too many tries. Wait a few minutes and try again." : fallback;
  }
}
