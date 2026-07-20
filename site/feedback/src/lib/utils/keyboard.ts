/** True if a keyboard shortcut fired while the user was already typing somewhere else
 * (an input, textarea, or contenteditable) — global shortcuts like "/" and "c" should
 * stand down rather than hijack the keystroke. */
export function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable;
}
