"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const NAV_LINKS = [{ href: "/admin", label: "Requests" }];

/**
 * The admin section's own nav — separate from `SiteHeader`'s public nav, since these
 * are internal-only tools.
 *
 * Games (/admin/games) and Site content (/studio, the embedded Sanity Studio) were
 * deliberately dropped from this nav — both routes still exist and work if you navigate
 * to them directly, they're just no longer surfaced as tabs here.
 */
export function AdminNav() {
  const pathname = usePathname();

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
    </div>
  );
}
