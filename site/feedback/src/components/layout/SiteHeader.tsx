"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { UserMenu } from "@/components/layout/UserMenu";
import { useIsAdmin } from "@/lib/auth/useIsAdmin";

// Same link set as MarketingHeader's NAV_LINKS, plus the board-only Changelog link —
// deliberately not just "Board"/"Changelog" alone, so the whole site is reachable from
// any page's navbar, matching marketing's navbar 1:1 in everything but this one addition.
const NAV_LINKS = [
  { href: "/", label: "Home" },
  { href: "/features", label: "Features" },
  { href: "/pricing", label: "Pricing" },
  { href: "/faq", label: "FAQ" },
  { href: "/feedback", label: "Feedback" },
];

const ADMIN_LINKS = [
  { href: "/admin", label: "Admin" },
  { href: "/admin/games", label: "Games" },
  { href: "/studio", label: "Studio" },
];

/** Board/admin/changelog/auth equivalent of MarketingHeader — same `.site-nav` markup
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

  useEffect(() => {
    setIsOpen(false);
  }, [pathname]);

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
            <li className="site-nav-divider" aria-hidden />
            <li>
              <Link href="/changelog" className={pathname === "/changelog" ? "is-active" : undefined}>
                Changelog
              </Link>
            </li>
            {isAdmin && (
              <>
                <li className="site-nav-divider" aria-hidden />
                {ADMIN_LINKS.map((link) => (
                  <li key={link.href}>
                    <Link href={link.href} className={pathname === link.href ? "is-active" : undefined}>
                      {link.label}
                    </Link>
                  </li>
                ))}
              </>
            )}
          </ul>
        </nav>
        <div className="site-nav-actions">
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
