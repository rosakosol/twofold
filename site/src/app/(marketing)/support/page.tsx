import type { Metadata } from "next";
import { Reveal } from "@/components/marketing/Reveal";
import { SupportForm } from "@/components/marketing/SupportForm";

export const metadata: Metadata = {
  title: "Support",
  description: "Get help with Twofold — questions about your account, a bug, or anything else. We read every message.",
};

export default function SupportPage() {
  return (
    <>
      <header className="page-head">
        <Reveal className="wrap">
          <span className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            Support
          </span>
          <h1>We&apos;re here to help</h1>
          <p className="lead">
            Tell us what&apos;s going on and we&apos;ll reply at the email you provide — usually within a day or two. Looking
            for a quick answer instead? Check the <a className="text-link" href="/faq">FAQ</a>.
          </p>
        </Reveal>
      </header>

      <section style={{ paddingTop: 20 }}>
        <div className="wrap-narrow">
          <Reveal>
            <SupportForm />
          </Reveal>
        </div>
      </section>
    </>
  );
}
