"use client";

import { evaluatePassword, passwordRejectionReason } from "@/lib/marketing/passwordStrength";

/**
 * The web twin of `PasswordStrengthView` in the app
 * (Twofold/Twofold/DesignSystem/Components/PasswordStrength.swift): three segments filling up to the
 * current strength, a label in the same colour, and the reason underneath.
 *
 * The hexes are the app's own. `--heart-red` and `--leaf-green` in marketing.css already hold
 * `Theme.heartRed` and `Theme.leafGreen`'s light values, and this repeats them literally rather than
 * reading the variables because the reset-password page lives in the (board) route and never loads
 * that stylesheet — a token would resolve to nothing there and the meter would render colourless on
 * the one screen where a refusal is most confusing.
 *
 * FAIR is SwiftUI's system orange, which is what the app passes for that case. Marketing has no
 * orange token to borrow and no dark mode to match, so the light value stands alone.
 */
const COLOR = {
  weak: "#e85c6b",
  fair: "#ff9500",
  strong: "#6fbf8b",
} as const;

const RANK = { weak: 0, fair: 1, strong: 2 } as const;

const LABEL = {
  weak: "Weak",
  fair: "Fair",
  strong: "Strong",
} as const;

export function PasswordStrengthMeter({
  password,
  name,
  email,
}: {
  password: string;
  name?: string;
  email?: string;
}) {
  // Nothing to say about an empty field, same as the app — the meter appears as you type.
  if (password === "") return null;

  const strength = evaluatePassword(password, name, email);
  const reason = passwordRejectionReason(password, name, email);
  const filled = RANK[strength];

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <div style={{ display: "flex", gap: 4, flex: "1 1 auto" }} aria-hidden="true">
          {[0, 1, 2].map((segment) => (
            <span
              key={segment}
              style={{
                flex: "1 1 0",
                height: 4,
                borderRadius: 999,
                background: segment <= filled ? COLOR[strength] : "rgba(91, 107, 122, 0.2)",
              }}
            />
          ))}
        </div>
        <span style={{ fontSize: "0.75rem", fontWeight: 600, color: COLOR[strength] }}>
          {LABEL[strength]}
        </span>
      </div>

      {/* Announced rather than only shown: the field is invalid and a sighted user learns that from
          the colour, which is not a channel a screen reader has. */}
      {reason && (
        <p style={{ fontSize: "0.75rem", opacity: 0.8, margin: 0 }} role="status" aria-live="polite">
          {reason}
        </p>
      )}
    </div>
  );
}
