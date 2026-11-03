import type { Metadata } from "next";
import { Newsreader } from "next/font/google";
import "./globals.css";
import { Providers } from "@/app/providers";
import { THEME_INIT_SCRIPT } from "@/lib/theme/themeScript";
import { SITE_URL } from "@/lib/mail/companyInfo";

// Text uses the system faces the app does, SF and New York on Apple devices (--font-body and
// --font-display in src/styles/tokens.css, docs/TWOFOLD_WEBSITE.md section 2.3). The one web font
// is the wordmark's: Newsreader (OFL), so "twofold" looks the same on every device. New York
// itself can't be served: Apple licenses it for mock-ups, not for embedding.
const wordmarkFont = Newsreader({
  variable: "--font-wordmark",
  subsets: ["latin"],
  weight: "400",
});

const DESCRIPTION =
  "Twofold helps long distance couples stay connected - track flights, share memories and grow closer with games.";

// metadataBase makes every relative URL below absolute, which link previews need. Open Graph and
// Twitter fields are inherited by every page that doesn't set its own, so a shared link gets a
// title, a description and an image instead of a bare URL. The image is the app icon for now;
// a wide `app/opengraph-image.png` would replace it here without any code change.
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Twofold - Long Distance Couples App",
    template: "%s | Twofold",
  },
  description: DESCRIPTION,
  openGraph: {
    type: "website",
    siteName: "Twofold",
    locale: "en_AU",
    title: "Twofold - Long Distance Couples App",
    description: DESCRIPTION,
    images: [{ url: "/app-icon.png", width: 256, height: 256, alt: "Twofold" }],
  },
  twitter: { card: "summary" },
};

// Deliberately minimal — no header/footer here. (marketing) and (board) each render
// their own (different visual systems, see their own layout.tsx), so this only owns
// what's genuinely global: fonts, the light/dark choice and app-wide providers (TanStack Query,
// toasts).
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    // suppressHydrationWarning: <html> is changed before React hydrates it, by the theme script
    // below (data-theme) and by DeviceClassSetter (its classes).
    <html lang="en" className={`no-js ${wordmarkFont.variable}`} suppressHydrationWarning>
      <head>
        {/* The stored light/dark choice, applied before first paint (lib/theme/themeScript.ts).
            A fixed string of our own: the one dangerouslySetInnerHTML in the app, and no input
            reaches it. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
      </head>
      <body className="antialiased min-h-screen flex flex-col">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
