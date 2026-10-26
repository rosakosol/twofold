// The app screens the site shows, captured from the real app by scripts/capture-site-screens.sh
// (the app's -demoMode: Sam in Melbourne, Alex in Rome). Each exists as
// public/assets/phone-screen/<key>-light-<n>.webp and <key>-dark-<n>.webp (n = CAPTURE_SET below),
// the bare screen with no frame:
// PhoneMockup draws the phone around it and shows the one matching the visitor's appearance.
//
// Re-run the script when the app's look changes. A new screen needs a line here and one in the
// script's SCREENS list, with the same key.

/** Pixel size of every capture (1179x2556, a 6.1-inch iPhone at 3x). */
export const PHONE_SHOT_WIDTH = 1179;
export const PHONE_SHOT_HEIGHT = 2556;

/** What each screen shows, for its alt text (docs/TWOFOLD_WEBSITE.md, section 10: describe the
 *  screen, never "app screenshot"). */
export const PHONE_SCREENS = {
  home: "Twofold's Home screen: 11:24 pm for Alex in Rome, Alex's Emirates flight EK96 from Rome to Dubai en route and landing in 55 minutes, and the 15,966 km between them",
  "travel-trips": "The Travel tab: a globe, and their upcoming trips, Rome to Melbourne in 22 days, Melbourne to Rome in 98 and Melbourne to Tokyo in 119",
  "travel-flights": "The Travel tab on Flights: Alex's Emirates flight EK96 from Rome to Dubai, en route and landing in 55 minutes, and a past flight from Melbourne to Singapore",
  "memories-map": "The Memories map of Rome, with photo pins where their memories happened",
  "memory-detail": "A memory called Our first date, at Trattoria Pizzeria Luzzi in Rome, with a photo and a note",
  games: "The Games tab: start a streak, today's deep question, and the couple games",
  connected: "The screen that says You're connected, with Alex and Sam's photos joined by a heart",
  "our-story": "Our story: 4 moments together, a timeline of their trips between Melbourne, Osaka and Tokyo",
  // Captured by hand on a device: the script's simulator launches can't reach the Lock Screen.
  "lock-screen": "The Lock Screen: 22 days until Melbourne, Alex and Sam 15,966 km apart, and a Live Activity for Alex's Emirates flight EK96 to Dubai, 55 minutes to landing",
} as const;

export type PhoneScreen = keyof typeof PHONE_SCREENS;

/** Bumped whenever the captures are replaced: the image optimiser caches by URL, so a new capture
 *  under an old file name can keep serving the old picture. Rename the files to match. */
const CAPTURE_SET = 6;

export function phoneScreenSrc(screen: PhoneScreen, mode: "light" | "dark") {
  return `/assets/phone-screen/${screen}-${mode}-${CAPTURE_SET}.webp`;
}
