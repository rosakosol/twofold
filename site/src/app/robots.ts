import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/mail/companyInfo";

/** The public site and the feedback board; nothing behind a sign-in, and no API. */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // /unsubscribe is left crawlable on purpose: it sends noindex itself, which a blocked page
      // never gets to say.
      disallow: ["/admin", "/studio", "/account", "/auth", "/api"],
    },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
