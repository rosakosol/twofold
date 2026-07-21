import "@/styles/site-nav.css";
import { SiteHeader } from "@/components/layout/SiteHeader";
import { SiteFooter } from "@/components/layout/SiteFooter";

// Feedback board, admin, changelog, auth — the shadcn/Tailwind-styled half of the app,
// as opposed to (marketing)'s ported site/styles.css. Split into its own group
// specifically so each can own its own header/footer without colliding. `board-shell`
// (globals.css) scopes the sans-serif/compact typography pass to just this half of the
// app, leaving the marketing route group's own type system untouched.
export default function BoardLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="board-shell flex min-h-screen flex-1 flex-col">
      <SiteHeader />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}
