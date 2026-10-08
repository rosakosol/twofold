"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu, SlidersHorizontal, X } from "lucide-react";
import { UserMenu } from "@/components/layout/UserMenu";
import { SignedInNavItems } from "@/components/layout/SignedInNavItems";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import { useAdminRoles } from "@/lib/auth/useAdminRoles";
import { Wordmark } from "@/components/layout/Wordmark";

/** The header's destinations (docs/TWOFOLD_WEBSITE.md, section 3). The wordmark is the way home. */
const NAV_LINKS = [
  { href: "/features", label: "Features" },
  { href: "/pricing", label: "Pricing" },
  { href: "/faq", label: "FAQ" },
  { href: "/feedback", label: "Feedback" },
];

function isCurrent(pathname: string, href: string) {
  return pathname === href || pathname.startsWith(`${href}/`);
}

/**
 * The website's one header, for the marketing pages and the feedback board, account and sign-in
 * pages alike. The console has its own (ConsoleHeader), on purpose.
 *
 * 72px: the wordmark, the nav pills, then on the right the light/dark toggle and Download (signed
 * out) or the account chip (signed in). On a phone the pills fold into a menu behind a 44px
 * button; the toggle stays in the bar.
 */
export function SiteHeader() {
  const pathname = usePathname();
  // Any role at all gets the door to the console, matching is_console_admin on the server.
  const roles = useAdminRoles();
  const isAdmin = roles.content || roles.support || roles.billing;
  const [isScrolled, setIsScrolled] = useState(false);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    function handleScroll() {
      setIsScrolled(window.scrollY > 8);
    }
    handleScroll();
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  // Close the menu on navigation. Done during render rather than in an effect, so the menu never
  // paints open on the destination page.
  const [menuPathname, setMenuPathname] = useState(pathname);
  if (menuPathname !== pathname) {
    setMenuPathname(pathname);
    setIsOpen(false);
  }

  return (
    <header className={`site-nav${isScrolled ? " is-scrolled" : ""}${isOpen ? " is-open" : ""}`}>
      <div className="site-nav-inner">
        <Link className="site-nav-brand" href="/" aria-label="Twofold home">
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
          <img src="/assets/globe-heart.png" alt="" width={28} height={28} />
          <Wordmark />
        </Link>
        <nav aria-label="Main">
          <ul className="site-nav-links" id="site-nav-links">
            {NAV_LINKS.map((link) => {
              const current = isCurrent(pathname, link.href);
              return (
                <li key={link.href}>
                  <Link href={link.href} aria-current={current ? "page" : undefined}>
                    {link.label}
                  </Link>
                </li>
              );
            })}
            {/* Account, Bookmarks or Sign in: only in the folded menu, see SignedInNavItems. */}
            <SignedInNavItems />
            <ThemeToggle variant="menu-row" />
          </ul>
        </nav>
        <div className="site-nav-actions">
          {/* The console is its own shell; this is the one door into it, only for an admin. */}
          {isAdmin && (
            <Link href="/admin" className="site-nav-switch">
              <SlidersHorizontal aria-hidden />
              <span>Console</span>
            </Link>
          )}
          <ThemeToggle />
          <UserMenu />
          <button
            type="button"
            className="site-nav-toggle"
            aria-label={isOpen ? "Close menu" : "Open menu"}
            aria-expanded={isOpen}
            aria-controls="site-nav-links"
            onClick={() => setIsOpen((v) => !v)}
          >
            {isOpen ? <X aria-hidden /> : <Menu aria-hidden />}
          </button>
        </div>
      </div>
    </header>
  );
}
