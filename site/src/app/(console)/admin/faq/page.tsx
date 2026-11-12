"use client";

import { ConsolePageHead } from "@/components/console/ConsoleUI";
import { FaqEditor } from "@/components/admin/faq/FaqEditor";
import { useAdminRolesState } from "@/lib/auth/useAdminRoles";

/** The FAQ shared by the website's /faq page and the app's Support screen (faq_entries). It was a
 *  tool inside Sanity Studio until Studio moved to Sanity's hosting: see useFaqEntries.ts. */
export default function AdminFaqPage() {
  const { roles, isLoaded } = useAdminRolesState();
  return (
    <div>
      <ConsolePageHead
        title="FAQ"
        description="The questions on the website's FAQ page and in the app's Support screen. Changes show on both within about a minute."
      />
      {isLoaded && !roles.content && (
        <p className="field-hint">You can read the FAQ here, but changing it needs the content role.</p>
      )}
      <p className="field-hint mb-4">
        The website keeps a built-in copy for when the database can&apos;t be reached
        (src/lib/marketing/faqFallback.ts). Nothing updates it automatically, so an edit here also needs one there.
      </p>
      <FaqEditor />
    </div>
  );
}
