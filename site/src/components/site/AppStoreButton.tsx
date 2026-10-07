import { APP_STORE_URL } from "@/lib/marketing/config";

/** The App Store button (docs/TWOFOLD_WEBSITE.md, section 3): the primary button with the Apple
 *  glyph, "Download on the App Store" on one line, or "Open on the App Store" for someone who
 *  already has Twofold. */
export function AppStoreButton({
  size,
  label = "Download on the App Store",
  className,
}: {
  size?: "lg";
  label?: string;
  className?: string;
}) {
  return (
    <a
      className={["appstore-badge", size === "lg" ? "btn-lg" : null, className].filter(Boolean).join(" ")}
      data-appstore-link
      href={APP_STORE_URL}
    >
      <svg className="icon" aria-hidden>
        <use href="/assets/icons.svg#icon-apple" />
      </svg>
      {label}
    </a>
  );
}
