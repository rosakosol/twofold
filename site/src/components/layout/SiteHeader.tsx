"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { SlidersHorizontal } from "lucide-react";
import { UserMenu } from "@/components/layout/UserMenu";
import { useIsAdmin } from "@/lib/auth/useIsAdmin";

// Same link set as MarketingHeader's NAV_LINKS, so the whole site is reachable from any
// page's navbar, matching marketing's navbar 1:1.
const NAV_LINKS = [
  { href: "/", label: "Home" },
  { href: "/features", label: "Features" },
  { href: "/pricing", label: "Pricing" },
  { href: "/faq", label: "FAQ" },
  { href: "/feedback", label: "Feedback" },
];

/** Board/admin/auth equivalent of MarketingHeader — same `.site-nav` markup
 * and CSS (src/styles/site-nav.css) so the two navbars are pixel-identical, just with
 * UserMenu (sign-in/avatar) in place of the marketing "Get the App" CTA. */
export function SiteHeader() {
  const pathname = usePathname();
  const isAdmin = useIsAdmin();
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

  // Close the mobile menu on navigation. Done during render rather than in an effect: React
  // restarts the render with the new state before committing, so the menu never paints open
  // on the destination route the way an effect's extra commit would allow.
  const [menuPathname, setMenuPathname] = useState(pathname);
  if (menuPathname !== pathname) {
    setMenuPathname(pathname);
    setIsOpen(false);
  }

  return (
    <header className={`site-nav${isScrolled ? " is-scrolled" : ""}${isOpen ? " is-open" : ""}`}>
      <div className="site-nav-inner">
        <Link className="site-nav-brand" href="/">
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark, matches MarketingHeader's */}
          <img src="/assets/globe-heart.png" alt="" width={28} height={28} />
          <span>twofold</span>
        </Link>
        <nav>
          <ul className="site-nav-links">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <Link href={link.href} className={pathname === link.href ? "is-active" : undefined}>
                  {link.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
        <div className="site-nav-actions">
          {/* The console is a separate shell, not a row of extra links in this bar — see
              ConsoleHeader. One button crosses between them, and only for someone who has
              somewhere to cross to, so a normal visitor's navbar is unchanged by any of this. */}
          {isAdmin && (
            <Link href="/admin" className="site-nav-switch">
              <SlidersHorizontal className="h-3.5 w-3.5" />
              <span>Console</span>
            </Link>
          )}
          <UserMenu />
          <button
            type="button"
            className="site-nav-toggle"
            aria-label="Toggle menu"
            aria-expanded={isOpen}
            onClick={() => setIsOpen((v) => !v)}
          >
            <svg className="icon icon-menu">
              <use href="/assets/icons.svg#icon-menu" />
            </svg>
            <svg className="icon icon-x">
              <use href="/assets/icons.svg#icon-x" />
            </svg>
          </button>
        </div>
      </div>
    </header>
  );
}
