"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { UserMenu } from "@/components/layout/UserMenu";
import { AccountNavItem } from "@/components/layout/AccountNavItem";
import { APP_STORE_URL } from "@/lib/marketing/config";

const NAV_LINKS = [
  { href: "/", label: "Home" },
  { href: "/features", label: "Features" },
  { href: "/pricing", label: "Pricing" },
  { href: "/faq", label: "FAQ" },
  { href: "/feedback", label: "Feedback" },
];

/** Ported from site/assets/js/site.js's nav behavior: shadow after a small scroll,
 * mobile menu toggle, active-link highlighting. Reveal-on-scroll and device-class
 * detection live in their own hooks (useReveal / useDeviceClass) since other
 * components need those independently of the header. */
export function MarketingHeader() {
  const pathname = usePathname();
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
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark, matches the ported static markup as-is */}
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
            {/* Collapsed-menu only — the avatar dropdown is the desktop route. Above Download so
                the two navbars list the same destinations in the same order. */}
            <AccountNavItem />
            <li className="hide-on-desktop">
              <a data-appstore-link href={APP_STORE_URL}>
                Download
              </a>
            </li>
          </ul>
        </nav>
        <div className="site-nav-actions">
          {/* Where "Get the App" used to be. The App Store is still one tap away — the badge in the
              hero, the mobile "Download" item in the nav list above, and every appstore-badge on the
              page — so this slot is better spent on the one thing the navbar could not otherwise
              reach: which account you are. UserMenu renders the same `.site-nav-cta` pill when
              signed out, so the bar is unchanged until there is a session, and SiteHeader has used
              it here since the board group was split out. */}
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
