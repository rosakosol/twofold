import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/app/providers";
import { THEME_INIT_SCRIPT } from "@/lib/theme/themeScript";

// No web fonts: the site uses the system faces the app does, SF and New York on Apple devices
// (--font-body and --font-display in src/styles/tokens.css, docs/TWOFOLD_WEBSITE.md section 2.3).

export const metadata: Metadata = {
  title: {
    default: "Twofold - Long Distance Couples App",
    template: "%s | Twofold",
  },
  description: "Twofold helps long distance couples stay connected - track flights, share memories and grow closer with games.",
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
    <html lang="en" className="no-js" suppressHydrationWarning>
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
