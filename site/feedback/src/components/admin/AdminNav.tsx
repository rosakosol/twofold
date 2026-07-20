"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ExternalLink } from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_LINKS = [
  { href: "/admin", label: "Requests" },
  { href: "/admin/games", label: "Games" },
];

/**
 * The admin section's own nav — separate from `SiteHeader`'s public nav (Feedback /
 * Roadmap / Changelog), since these are internal-only tools. Also the "one space" entry
 * point out to Sanity Studio (marketing site content) so admins don't need to remember a
 * separate URL — hidden rather than linking to a 404 until the Studio is actually
 * deployed (see `.env.local.example`).
 */
export function AdminNav() {
  const pathname = usePathname();
  const studioUrl = process.env.NEXT_PUBLIC_SANITY_STUDIO_URL;

  return (
    <div className="mb-6 flex items-center justify-between border-b pb-3">
      <nav className="flex items-center gap-1">
        {NAV_LINKS.map((link) => {
          const isActive = link.href === "/admin" ? pathname === "/admin" : pathname.startsWith(link.href);
          return (
            <Link
              key={link.href}
              href={link.href}
              className={cn(
                "rounded-md px-3 py-1.5 text-sm transition-colors hover:bg-accent hover:text-foreground",
                isActive ? "bg-accent text-foreground" : "text-muted-foreground"
              )}
            >
              {link.label}
            </Link>
          );
        })}
      </nav>
      {studioUrl && (
        <a
          href={studioUrl}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          Site content (Sanity) <ExternalLink className="h-3.5 w-3.5" />
        </a>
      )}
    </div>
  );
}
