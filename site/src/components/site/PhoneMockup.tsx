import Image from "next/image";

/**
 * An app screenshot in a phone frame (docs/TWOFOLD_WEBSITE.md, section 3). The frame is drawn here,
 * so the screenshots in public/assets/phone-screen/ are the bare screen at its own size. Width and
 * height are the screenshot's pixel size, which next/image needs for the aspect ratio.
 */
export function PhoneMockup({
  src,
  alt,
  width,
  height,
  sizes = "(max-width: 760px) 70vw, 340px",
  priority = false,
  className,
}: {
  src: string;
  /** What the screen shows, not "app screenshot" (section 10). */
  alt: string;
  width: number;
  height: number;
  sizes?: string;
  priority?: boolean;
  className?: string;
}) {
  return (
    <figure className={["phone-mockup", className].filter(Boolean).join(" ")}>
      <div className="phone-bezel">
        <Image className="phone-screen" src={src} alt={alt} width={width} height={height} sizes={sizes} priority={priority} />
      </div>
    </figure>
  );
}
