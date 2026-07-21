import Link from "next/link";
import { APP_STORE_URL } from "@/lib/marketing/config";

export function MarketingFooter() {
  return (
    <footer className="footer">
      <div className="footer-inner">
        <div className="footer-brand">
          <div className="brand">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark, matches the ported static markup as-is */}
            <img src="/assets/globe-heart.png" alt="" width={22} height={22} />
            <span>twofold</span>
          </div>
          <p>The living map for long-distance couples. Track flights, close the distance, keep the memories.</p>
        </div>
        <div className="footer-col">
          <h4>Product</h4>
          <ul>
            <li>
              <Link href="/features">Features</Link>
            </li>
            <li>
              <Link href="/pricing">Pricing</Link>
            </li>
            <li>
              <Link href="/faq">FAQ</Link>
            </li>
            <li>
              <a data-appstore-link href={APP_STORE_URL}>
                Download on iOS
              </a>
            </li>
          </ul>
        </div>
        <div className="footer-col">
          <h4>Support</h4>
          <ul>
            <li>
              <a href="mailto:hello@twofoldapp.com.au">Contact us</a>
            </li>
            <li>
              <Link href="/faq#subscriptions">Manage subscription</Link>
            </li>
            <li>
              <Link href="/#waitlist">Android waitlist</Link>
            </li>
          </ul>
        </div>
        <div className="footer-col">
          <h4>Legal</h4>
          <ul>
            <li>
              <Link href="/privacy">Privacy Policy</Link>
            </li>
            <li>
              <Link href="/terms">Terms of Use</Link>
            </li>
          </ul>
        </div>
      </div>
      <div className="footer-bottom">
        <span>© {new Date().getFullYear()} Twofold. Made for the couples doing long distance.</span>
      </div>
    </footer>
  );
}
