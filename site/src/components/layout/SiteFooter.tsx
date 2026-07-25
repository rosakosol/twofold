import Link from "next/link";
import { APP_STORE_URL } from "@/lib/marketing/config";

/** Shared with both route groups (marketing + board) — one footer, so every page reads
 * as the same product no matter which layout renders it. Originally matched
 * design_handoff_twofold_site/*.html's 4-column footer exactly; since diverged
 * (Feedback added under Product, FAQ moved under Support, Manage Subscription/Android
 * waitlist links dropped, Contact us points at /support instead of a mailto link). */
export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="wrap">
        <div>
          <div className="brand">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
            <img src="/assets/globe-heart.png" alt="" />
            <span>twofold</span>
          </div>
          <p>The living map for long-distance couples. Track flights, close the distance, keep the memories.</p>
        </div>
        <div className="foot-col">
          <h4>Product</h4>
          <Link href="/features">Features</Link>
          <Link href="/pricing">Pricing</Link>
          <Link href="/feedback">Feedback</Link>
          <a
            className="appstore-badge foot-appstore"
            data-appstore-link
            href={APP_STORE_URL}
            aria-label="Download Twofold on the App Store"
          >
            <svg className="icon" aria-hidden>
              <use href="/assets/icons.svg#icon-apple" />
            </svg>
            <span className="badge-text">
              <small>Download on the</small>
              <strong>App&nbsp;Store</strong>
            </span>
          </a>
        </div>
        <div className="foot-col">
          <h4>Support</h4>
          <Link href="/support">Contact us</Link>
          <Link href="/faq">FAQ</Link>
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
