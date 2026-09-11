// Shared facts about the app screenshots in public/assets/phone-screen/.
//
// These PNGs are captured from the real app and already include the device frame. Both the
// home page and the features page render them, and both previously carried their own copy of
// the height — which had drifted to 1877 against files that are actually 2061 tall, silently
// squashing every screenshot on the site, since next/image takes the aspect ratio from the
// width/height it's given rather than from the file.
//
// Only the height is shared: widths vary because the frames aren't all the same crop.

/** Height in px of every export in public/assets/phone-screen/. */
export const PHONE_SHOT_HEIGHT = 2061;
