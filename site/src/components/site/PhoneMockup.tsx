import { getImageProps } from "next/image";
import { PHONE_SCREENS, PHONE_SHOT_HEIGHT, PHONE_SHOT_WIDTH, phoneScreenSrc, type PhoneScreen } from "@/lib/marketing/phoneScreens";

/**
 * An app screen in a phone frame (docs/TWOFOLD_WEBSITE.md, section 3). The screen is the light or
 * dark capture to match the visitor's appearance, chosen by the browser through <picture>, so it
 * costs no script and never flashes the wrong one.
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
  const {
    props: { srcSet: darkSrcSet },
  } = getImageProps({ ...common, src: phoneScreenSrc(screen, "dark") });
  const { props: light } = getImageProps({ ...common, src: phoneScreenSrc(screen, "light") });

  return (
    <figure className={["phone-mockup", className].filter(Boolean).join(" ")}>
      <div className="phone-bezel">
        <picture>
          <source media="(prefers-color-scheme: dark)" srcSet={darkSrcSet} sizes={sizes} />
          <img
            {...light}
            alt={alt}
            className="phone-screen"
            loading={eager ? "eager" : "lazy"}
            fetchPriority={eager ? "high" : undefined}
          />
        </picture>
      </div>
    </figure>
  );
}
