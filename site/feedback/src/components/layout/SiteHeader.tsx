import Link from "next/link";
import { UserMenu } from "@/components/layout/UserMenu";

const NAV_LINKS = [
  { href: "/feedback", label: "Feedback" },
  { href: "/roadmap", label: "Roadmap" },
  { href: "/changelog", label: "Changelog" },
];

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b bg-background/80 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-5xl items-center justify-between px-4">
        <div className="flex items-center gap-6">
          <Link href="/feedback" className="font-semibold tracking-tight">
            twofold <span className="text-muted-foreground font-normal">feedback</span>
          </Link>
          <nav className="hidden sm:flex items-center gap-1">
            {NAV_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
              >
                {link.label}
              </Link>
            ))}
          </nav>
        </div>
        <UserMenu />
      </div>
    </header>
  );
}
