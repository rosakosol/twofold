import "@/styles/site-nav.css";
import "./marketing.css";
import { MarketingHeader } from "@/components/marketing/MarketingHeader";
import { MarketingFooter } from "@/components/marketing/MarketingFooter";
import { DeviceClassSetter } from "@/components/marketing/DeviceClassSetter";

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 flex-col">
      <DeviceClassSetter />
      <MarketingHeader />
      <main id="top" className="flex-1">
        {children}
      </main>
      <MarketingFooter />
    </div>
  );
}
