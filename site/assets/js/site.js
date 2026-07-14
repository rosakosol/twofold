// Twofold — shared page behaviour (nav, reveal-on-scroll, device-aware CTAs).
// Loaded on every page. No build step / no bundler by design — plain ES module.

import { APP_STORE_URL } from "/assets/js/config.js";

document.documentElement.classList.remove("no-js");

// Footer year
document.querySelectorAll("[data-year]").forEach((el) => {
  el.textContent = new Date().getFullYear();
});

// App Store links: fill in the shared placeholder everywhere so there's one source of truth.
document.querySelectorAll("[data-appstore-link]").forEach((el) => {
  el.setAttribute("href", APP_STORE_URL);
});

// Mobile nav toggle
const nav = document.querySelector(".nav");
const navToggle = document.querySelector(".nav-toggle");
if (nav && navToggle) {
  navToggle.addEventListener("click", () => {
    const isOpen = nav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });
  nav.querySelectorAll(".nav-links a").forEach((link) => {
    link.addEventListener("click", () => {
      nav.classList.remove("is-open");
      navToggle.setAttribute("aria-expanded", "false");
    });
  });
}

// Nav shadow/background once scrolled
if (nav) {
  const onScroll = () => {
    nav.classList.toggle("is-scrolled", window.scrollY > 8);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
}

// Active nav link for the current page
const currentPath = window.location.pathname.replace(/index\.html$/, "").replace(/\/$/, "") || "/";
document.querySelectorAll(".nav-links a[href]").forEach((link) => {
  const linkPath = new URL(link.getAttribute("href"), window.location.origin).pathname
    .replace(/index\.html$/, "")
    .replace(/\/$/, "") || "/";
  if (linkPath === currentPath) link.classList.add("is-active");
});

// Reveal-on-scroll
const revealEls = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window && revealEls.length) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
  );
  revealEls.forEach((el) => observer.observe(el));
} else {
  revealEls.forEach((el) => el.classList.add("is-visible"));
}

// Device-aware CTA routing — web2app funnels convert better when the primary CTA
// matches the device: send iOS/Android visitors to the App Store, send desktop
// visitors into the web checkout instead of a dead-end store badge.
const ua = navigator.userAgent || "";
const isIOS = /iPhone|iPad|iPod/.test(ua) || (ua.includes("Macintosh") && navigator.maxTouchPoints > 1);
const isAndroid = /Android/.test(ua);
const isMobile = isIOS || isAndroid;
document.documentElement.classList.add(isMobile ? "is-mobile" : "is-desktop");
document.documentElement.classList.add(isIOS ? "is-ios" : isAndroid ? "is-android" : "is-other-os");
