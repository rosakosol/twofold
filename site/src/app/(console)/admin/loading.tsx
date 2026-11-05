import { Skeleton } from "@/components/ui/skeleton";

/** Loading state for the /admin pages, shaped like admin/page.tsx (heading, filter row, table)
 * so the swap to real content doesn't jump.
 *
 * What it does not cover: the (console) layout's sign-in and `consoleGate` sits above
 * this segment, and a loading.tsx never wraps the layout of its own or a parent segment
 * (node_modules/next/dist/docs/01-app/03-api-reference/03-file-conventions/loading.md). So the
 * first entry into the console still waits for that gate. Moving between /admin pages keeps the
 * shared layout without re-running it, which is where this skeleton shows. */
export default function Loading() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-6 flex items-center justify-between border-b pb-3">
        <Skeleton className="h-8 w-24 rounded-md" />
      </div>
      <Skeleton className="h-7 w-32" />
      <Skeleton className="mt-2 h-4 w-48" />
      <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center">
        <Skeleton className="h-9 w-full rounded-full sm:max-w-xs sm:flex-1" />
        <Skeleton className="h-8 w-36 rounded-md" />
        <Skeleton className="h-8 w-36 rounded-md" />
      </div>
      <Skeleton className="mt-6 h-64 w-full rounded-lg" />
    </div>
  );
}
