"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
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

  useEffect(() => {
    setIsOpen(false);
  }, [pathname]);

  return (
    <header className={`site-nav${isScrolled ? " is-scrolled" : ""}${isOpen ? " is-open" : ""}`}>
      <div className="site-nav-inner">
        <Link className="site-nav-brand" href="/">
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark, matches the ported static markup as-is */}
          <img src="/assets/app-icon.png" alt="" width={28} height={28} />
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
            <li className="hide-on-desktop">
              <a data-appstore-link href={APP_STORE_URL}>
                Download
              </a>
            </li>
          </ul>
        </nav>
        <div className="site-nav-actions">
          <a className="site-nav-cta site-nav-cta-desktop" data-appstore-link href={APP_STORE_URL}>
            Get the App
          </a>
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
