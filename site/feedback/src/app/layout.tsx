import type { Metadata } from "next";
import { Inter, Newsreader } from "next/font/google";
import "./globals.css";
import { Providers } from "@/app/providers";
import { SiteHeader } from "@/components/layout/SiteHeader";
import { SiteFooter } from "@/components/layout/SiteFooter";

// Same two families the marketing site uses (site/styles.css's --font-body/--font-display)
// — this app is embedded under twofoldapp.com.au/feedback now, so it needs to look like
// the same site rather than a generic shadcn tool bolted onto it.
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
    default: "Twofold Feedback",
    template: "%s | Twofold Feedback",
  },
  description: "Request features, vote, and follow what's next for Twofold.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${bodyFont.variable} ${displayFont.variable} antialiased min-h-screen flex flex-col`}>
        <Providers>
          <SiteHeader />
          <main className="flex-1">{children}</main>
          <SiteFooter />
        </Providers>
      </body>
    </html>
  );
}
