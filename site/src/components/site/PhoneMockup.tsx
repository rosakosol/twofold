import { getImageProps } from "next/image";
import { PHONE_SCREENS, PHONE_SHOT_HEIGHT, PHONE_SHOT_WIDTH, phoneScreenSrc, type PhoneScreen } from "@/lib/marketing/phoneScreens";

/**
 * An app screen in a phone frame (docs/TWOFOLD_WEBSITE.md, section 3). The screen is the light or
 * dark capture to match the page's theme, picked by CSS (`.theme-*-only` in tokens.css), so it
 * costs no script and never flashes the wrong one.
 *
 * Not a plain <picture>: its prefers-color-scheme <source> follows the system and cannot see the
 * header's toggle. Both captures are in the markup instead, lazy, and a lazy image that is
 * display: none is never fetched, so only the one showing downloads.
 *
 * An `eager` phone (the home hero) cannot be lazy, and both captures eager would fetch both. So it
 * keeps the <picture> for visitors following the system, which is nearly everyone and fetches one,
 * and adds the lazy pair for those who have chosen, who fetch the <picture>'s capture as well.
 */
export function PhoneMockup({
  screen,
  alt = PHONE_SCREENS[screen],
  sizes = "(max-width: 760px) 70vw, 340px",
  eager = false,
  className,
}: {
  screen: PhoneScreen;
  /** Defaults to the screen's description in phoneScreens.ts. */
  alt?: string;
  sizes?: string;
  /** For a phone above the fold: loaded straight away and at high priority. */
  eager?: boolean;
  className?: string;
}) {
  const common = { alt, width: PHONE_SHOT_WIDTH, height: PHONE_SHOT_HEIGHT, sizes };
  const { props: light } = getImageProps({ ...common, src: phoneScreenSrc(screen, "light") });
  const { props: dark } = getImageProps({ ...common, src: phoneScreenSrc(screen, "dark") });
  const chosen = eager ? " theme-chosen-only" : "";

  return (
    <figure className={["phone-mockup", className].filter(Boolean).join(" ")}>
      <div className="phone-bezel">
        {eager && (
          <picture className="theme-system-only">
            <source media="(prefers-color-scheme: dark)" srcSet={dark.srcSet} sizes={sizes} />
            <img {...light} alt={alt} className="phone-screen" loading="eager" fetchPriority="high" />
          </picture>
        )}
        {/* eslint-disable-next-line @next/next/no-img-element -- getImageProps output, see above */}
        <img {...light} alt={alt} className={`phone-screen theme-light-only${chosen}`} loading="lazy" />
        {/* eslint-disable-next-line @next/next/no-img-element -- getImageProps output, see above */}
        <img {...dark} alt={alt} className={`phone-screen theme-dark-only${chosen}`} loading="lazy" />
      </div>
    </figure>
  );
}
