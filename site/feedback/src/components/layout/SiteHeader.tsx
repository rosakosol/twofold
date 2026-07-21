"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { UserMenu } from "@/components/layout/UserMenu";
import { cn } from "@/lib/utils";

const MARKETING_LINKS = [
  { href: "/", label: "Home" },
  { href: "/features", label: "Features" },
  { href: "/pricing", label: "Pricing" },
  { href: "/faq", label: "FAQ" },
];

const BOARD_LINKS = [
  { href: "/feedback", label: "Board" },
  { href: "/changelog", label: "Changelog" },
];

const NAV_LINK_CLASS =
  "rounded-md px-3 py-1.5 text-sm font-semibold text-subtle-ink transition-colors hover:text-foreground";

export function SiteHeader() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-40 border-b border-[var(--border-soft)] bg-[var(--nav-bg)] backdrop-blur-[14px]">
      <div className="mx-auto flex h-14 max-w-5xl items-center justify-between px-4">
        <div className="flex items-center gap-6">
          <Link href="/" className="flex items-center gap-2 font-heading text-[18px] font-bold tracking-tight text-foreground">
            {/* eslint-disable-next-line @next/next/no-img-element -- tiny fixed-size brand mark, not worth next/image's extra config here */}
            <img src="/assets/globe-heart.png" alt="" width={22} height={22} />
            twofold
          </Link>
          <nav className="hidden items-center gap-1 sm:flex">
            {MARKETING_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={cn(NAV_LINK_CLASS, pathname === link.href && "text-foreground")}
              >
                {link.label}
              </Link>
            ))}
            <span className="mx-1 h-4 w-px bg-[var(--border-soft)]" aria-hidden />
            {BOARD_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={cn(NAV_LINK_CLASS, pathname === link.href && "text-foreground")}
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
