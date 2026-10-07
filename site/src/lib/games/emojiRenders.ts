"use client";

import { useSyncExternalStore } from "react";

const cache = new Map<string, boolean>();

/** Draws the emoji on a small canvas and checks for colour: an emoji is in colour, and the
 *  missing-glyph box is not. Cached, so each emoji is drawn once per page. */
function measure(emoji: string): boolean | null {
  const known = cache.get(emoji);
  if (known !== undefined) return known;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 32;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) return null;
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
  return colourful;
}

const subscribe = () => () => {};

/**
 * Whether this device draws `emoji` as an emoji, or as a box. A deck's icon is an emoji, and a
 * newer one (a teapot, say) shows as an empty box on a device whose fonts predate it, which nobody
 * notices from a machine that has them. Null on the server and for no emoji.
 */
export function useEmojiRenders(emoji: string | null | undefined): boolean | null {
  return useSyncExternalStore(
    subscribe,
    () => (emoji ? measure(emoji) : null),
    () => null,
  );
}
