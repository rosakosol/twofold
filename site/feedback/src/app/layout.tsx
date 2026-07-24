import type { Metadata } from "next";
import { Inter, Newsreader } from "next/font/google";
import "./globals.css";
import { Providers } from "@/app/providers";

// Same two families the marketing site uses (site/styles.css's --font-body/--font-display)
// — loaded once here since both the marketing route group and the (board) group
// (feedback/admin/auth) share them, just applied via different stylesheets.
const bodyFont = Inter({
  variable: "--font-body",
  subsets: ["latin"],
});

const displayFont = Newsreader({
  variable: "--font-display",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: {
    default: "Twofold",
    template: "%s | Twofold",
  },
  description: "The living map for long-distance couples.",
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
      <body className={`${bodyFont.variable} ${displayFont.variable} antialiased min-h-screen flex flex-col`}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
