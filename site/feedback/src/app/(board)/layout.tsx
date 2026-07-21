import { SiteHeader } from "@/components/layout/SiteHeader";
import { SiteFooter } from "@/components/layout/SiteFooter";

// Feedback board, admin, changelog, auth — the shadcn/Tailwind-styled half of the app,
// as opposed to (marketing)'s ported site/styles.css. Split into its own group
// specifically so each can own its own header/footer without colliding.
export default function BoardLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 flex-col">
      <SiteHeader />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}
