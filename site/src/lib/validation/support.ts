import { isPlainEmailAddress } from "@/lib/validation/email";

/**
 * The web support form's rules, shared by the form (src/components/marketing/SupportForm.tsx) and
 * the route that enforces them (src/app/api/support/route.ts).
 *
 * The form used to check nothing (noValidate, no maxLength) while the route capped the message at
 * 5000 and the name at 200, so somebody typed a long message and only learned it was too long
 * after sending, from one form-level line that didn't say which field was wrong.
 */

// Same category list as the iOS app's own support form (HelpService.SupportRequestCategory) and
// supabase/functions/submit-help-message. Keep them in sync if categories change there. The app's
// "Report Abuse" is deliberately not offered on the web.
export const SUPPORT_CATEGORIES = [
  "Account & Subscription",
  "Bug Report",
  "Flight Tracking",
  "Trips & Memories",
  "Game Issue",
  "Feature Request",
  "Feedback",
  "Other",
] as const;

export type SupportCategory = (typeof SUPPORT_CATEGORIES)[number];

export const MAX_NAME_LENGTH = 200;
export const MAX_MESSAGE_LENGTH = 5000;
export const MAX_EMAIL_LENGTH = 320;

export type SupportField = "name" | "email" | "category" | "message";

export interface SupportRequestInput {
  name?: string;
  email?: string;
  category?: string;
  message?: string;
}

export type SupportValidation =
  | { ok: true; value: { name: string; email: string; category: SupportCategory; message: string } }
  | { ok: false; field: SupportField; error: string };

/** Checked in the order the form shows its fields' errors; the first failure wins. */
export function validateSupportRequest(input: SupportRequestInput): SupportValidation {
  const name = (input.name ?? "").trim();
  const email = (input.email ?? "").trim().toLowerCase();
  const category = (input.category ?? "").trim();
  const message = (input.message ?? "").trim();

  if (!email || !isPlainEmailAddress(email) || email.length > MAX_EMAIL_LENGTH) {
    return { ok: false, field: "email", error: "Enter a valid email address." };
  }
  if (!SUPPORT_CATEGORIES.includes(category as SupportCategory)) {
    return { ok: false, field: "category", error: "Choose a category." };
  }
  if (!message) return { ok: false, field: "message", error: "Enter a message." };
  if (message.length > MAX_MESSAGE_LENGTH) return { ok: false, field: "message", error: "Message is too long." };
  // It reaches an email template.
  if (name.length > MAX_NAME_LENGTH) return { ok: false, field: "name", error: "Name is too long." };

  return { ok: true, value: { name, email, category: category as SupportCategory, message } };
}
