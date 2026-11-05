import type { Metadata } from "next";
import { ConsolePageHead } from "@/components/console/ConsoleUI";
import { MfaSecurity } from "@/components/console/MfaSecurity";

export const metadata: Metadata = { title: "Security" };

/** An admin's own second factor. Behind the console door like everything else here, which means
 *  aal2 for anyone who has a factor; the first enrolment happens at /admin/mfa or here. */
export default function SecurityPage() {
  return (
    <div className="account-page">
      <ConsolePageHead title="Security" description="How your own admin account is protected." />
      <MfaSecurity />
    </div>
  );
}
