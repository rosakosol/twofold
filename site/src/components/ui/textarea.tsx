import * as React from "react"

import { cn } from "@/lib/utils"

// resize-none: field-sizing-content already grows the box with its text, so the native resize
// grip had nothing left to do. Worse, the browser draws it in the square corner of the box, which
// the 22px radius curves away from, so it sat outside the visible border; and dragging it pins a
// fixed height that stops the box growing. Where field-sizing is unsupported (Firefox), the box
// keeps its `rows` height and scrolls.
function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return (
    <textarea
      data-slot="textarea"
      className={cn(
        "flex field-sizing-content min-h-16 w-full resize-none rounded-[22px] border border-input bg-surface px-5 py-3 text-base transition-colors placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50 aria-invalid:border-[1.5px] aria-invalid:border-destructive md:text-sm",
        className
      )}
      {...props}
    />
  )
}

export { Textarea }
