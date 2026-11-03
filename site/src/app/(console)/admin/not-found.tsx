import Link from "next/link";
import { ConsoleEmpty, ConsolePageHead } from "@/components/console/ConsoleUI";

/** `notFound()` from a console page (an unknown account id, say), inside the console's chrome. */
export default function ConsoleNotFound() {
  return (
    <div>
      <ConsolePageHead title="Not found" />
      <ConsoleEmpty title="There's nothing at this address">
        The link may be mistyped, or what it pointed to has been deleted.{" "}
        <Link href="/admin/users" className="underline">
          Find an account
        </Link>
        .
      </ConsoleEmpty>
    </div>
  );
}
