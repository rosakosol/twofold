export function SiteFooter() {
  return (
    <footer className="border-t mt-16">
      <div className="mx-auto max-w-5xl px-4 py-8 text-sm text-muted-foreground flex items-center justify-between">
        <span>&copy; {new Date().getFullYear()} Twofold</span>
        <a href="https://twofoldapp.com.au" className="hover:text-foreground transition-colors">
          twofoldapp.com.au
        </a>
      </div>
    </footer>
  );
}
