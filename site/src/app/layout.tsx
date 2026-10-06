import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/app/providers";

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
// what's genuinely global: fonts and app-wide providers (TanStack Query, toasts).
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="no-js" suppressHydrationWarning>
      <body className="antialiased min-h-screen flex flex-col">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
