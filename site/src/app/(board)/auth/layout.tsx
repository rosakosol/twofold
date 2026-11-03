import type { Metadata } from "next";

// Sign-in, password reset and the auth callback are client pages, which can't export metadata
// themselves. None of them is worth a search result.
export const metadata: Metadata = { title: "Sign in", robots: { index: false, follow: false } };

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return children;
}
