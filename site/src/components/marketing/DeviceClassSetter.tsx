"use client";

import { useEffect } from "react";

/** Ported from site/assets/js/site.js — adds is-mobile/is-desktop and is-ios/
 * is-android/is-other-os classes to <html> via UA sniffing, which marketing.css's
 * .only-mobile/.only-desktop/.hide-on-mobile/.hide-on-desktop rules key off of for the
 * web2app funnel (mobile visitors see the App Store button front and center; desktop
 * visitors get a QR code instead). Renders nothing — side-effect only, mounted once in
 * the (marketing) layout. */
export function DeviceClassSetter() {
  useEffect(() => {
    const html = document.documentElement;
    html.classList.remove("no-js");

    const ua = navigator.userAgent || "";
    const isTouchPrimary = navigator.maxTouchPoints > 0 && /Mobi|Android|iPhone|iPad|iPod/i.test(ua);
    html.classList.add(isTouchPrimary ? "is-mobile" : "is-desktop");

    if (/iPhone|iPad|iPod/i.test(ua)) html.classList.add("is-ios");
    else if (/Android/i.test(ua)) html.classList.add("is-android");
    else html.classList.add("is-other-os");
  }, []);

  return null;
}
