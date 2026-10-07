"use client";

import { useEffect, useState } from "react";

const cache = new Map<string, boolean>();

/**
 * Whether this device draws `emoji` as an emoji, or as a box. A deck's icon is an emoji, and a
 * newer one (a teapot, say) shows as an empty box on a device whose fonts predate it, which nobody
 * notices from a machine that has them.
 *
 * Drawn on a small canvas and checked for colour: an emoji is in colour, and the missing-glyph box
 * is not. Null until checked, and on the server.
 */
export function useEmojiRenders(emoji: string | null | undefined): boolean | null {
  const [renders, setRenders] = useState<boolean | null>(() => (emoji ? (cache.get(emoji) ?? null) : null));

  useEffect(() => {
    if (!emoji) return;
    const known = cache.get(emoji);
    if (known !== undefined) {
      setRenders(known);
      return;
    }
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 32;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    if (!ctx) return;
    ctx.textBaseline = "top";
    ctx.font = "28px sans-serif";
    ctx.fillText(emoji, 0, 0);
    const { data } = ctx.getImageData(0, 0, 32, 32);
    let colourful = false;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] > 0 && (Math.abs(data[i] - data[i + 1]) > 20 || Math.abs(data[i + 1] - data[i + 2]) > 20)) {
        colourful = true;
        break;
      }
    }
    cache.set(emoji, colourful);
    setRenders(colourful);
  }, [emoji]);

  return renders;
}
