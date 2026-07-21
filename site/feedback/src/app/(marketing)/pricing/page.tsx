import type { Metadata } from "next";
import { PricingClient } from "@/components/marketing/PricingClient";

export const metadata: Metadata = {
  title: "Pricing",
  description: "Twofold Plus and Premium pricing. Subscribe on the web or in the app — either partner's subscription unlocks it for both of you.",
};

export default function PricingPage() {
  return <PricingClient />;
}
