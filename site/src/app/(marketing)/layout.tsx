import "@/styles/site-nav.css";
import "@/styles/site-footer.css";
import "./marketing.css";
import { SiteHeader } from "@/components/layout/SiteHeader";
import { SiteFooter } from "@/components/layout/SiteFooter";
import { DeviceClassSetter } from "@/components/marketing/DeviceClassSetter";

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="marketing-shell flex min-h-screen flex-1 flex-col">
      <DeviceClassSetter />
      <SiteHeader />
      <main id="top" className="flex-1">
        {children}
      </main>
      <SiteFooter />
    </div>
  );
}
