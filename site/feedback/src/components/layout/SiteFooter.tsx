import Link from "next/link";
import { APP_STORE_URL } from "@/lib/marketing/config";

/** Shared with both route groups (marketing + board) — one footer, matching
 * design_handoff_twofold_site/*.html's 4-column footer exactly, so every page reads
 * as the same product no matter which layout renders it. */
export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="wrap">
        <div>
          <div className="brand">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
            <img src="/assets/app-icon.png" alt="" />
            <span>twofold</span>
          </div>
          <p>The living map for long-distance couples. Track flights, close the distance, keep the memories.</p>
        </div>
        <div className="foot-col">
          <h4>Product</h4>
          <Link href="/features">Features</Link>
          <Link href="/pricing">Pricing</Link>
          <Link href="/faq">FAQ</Link>
          <a data-appstore-link href={APP_STORE_URL}>
            Download on iOS
          </a>
        </div>
        <div className="foot-col">
          <h4>Support</h4>
          <a href="mailto:hello@twofoldapp.com.au">Contact us</a>
          <Link href="/faq#subscriptions">Manage subscription</Link>
          <Link href="/#waitlist">Android waitlist</Link>
        </div>
        <div className="foot-col">
          <h4>Legal</h4>
          <Link href="/privacy">Privacy Policy</Link>
          <Link href="/terms">Terms of Use</Link>
        </div>
      </div>
      <div className="foot-base">
        <div className="wrap">
          <span>&copy; {new Date().getFullYear()} Twofold. Made for the couples doing long distance.</span>
          <span>twofoldapp.com.au</span>
        </div>
      </div>
    </footer>
  );
}
