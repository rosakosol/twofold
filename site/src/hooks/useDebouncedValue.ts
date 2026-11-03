"use client";

import { useEffect, useState } from "react";

/** `value`, once it has stopped changing for `delayMs`. The same 300ms the board's SearchBar uses. */
export function useDebouncedValue<T>(value: T, delayMs = 300): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timeout = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(timeout);
  }, [value, delayMs]);
  return debounced;
}
