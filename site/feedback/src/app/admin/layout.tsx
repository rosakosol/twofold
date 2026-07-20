import { redirect } from "next/navigation";
import { isFeedbackAdmin } from "@/lib/auth/isAdmin";
import { AdminNav } from "@/components/admin/AdminNav";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const isAdmin = await isFeedbackAdmin();
  if (!isAdmin) redirect("/");

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <AdminNav />
      {children}
    </div>
  );
}
