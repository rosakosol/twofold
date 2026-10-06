// The app screens the site shows, captured from the real app by scripts/capture-site-screens.sh
// (the app's -demoMode: Sam in Melbourne, Alex in Rome). Each exists as
// public/assets/phone-screen/<key>-light.webp and <key>-dark.webp, the bare screen with no frame:
// PhoneMockup draws the phone around it and shows the one matching the visitor's appearance.
//
// Re-run the script when the app's look changes. A new screen needs a line here and one in the
// script's SCREENS list, with the same key.

/** Pixel size of every capture (iPhone 17 Pro at 3x). */
export const PHONE_SHOT_WIDTH = 1206;
export const PHONE_SHOT_HEIGHT = 2622;

/** What each screen shows, for its alt text (docs/TWOFOLD_WEBSITE.md, section 10: describe the
 *  screen, never "app screenshot"). */
export const PHONE_SCREENS = {
  home: "Twofold's Home screen: Alex's time and weather in Rome, Alex's flight to Melbourne in the air, and the distance between them",
  "travel-trips": "The Travel tab: a globe with their routes, and the list of trips, Rome to Melbourne now and Melbourne to Tokyo in 58 days",
  "travel-flights": "The Travel tab on Flights: Alex's flight from Doha to Melbourne, en route and arriving in 1 hour 47 minutes",
  "flight-tracking": "Alex's journey: flight QR904 from Doha to Melbourne on a live map, with gate and terminal details",
  "trip-details": "Trip details for Alex's trip from Rome to Melbourne, with both flights and their status",
  "memories-map": "The Memories map of Rome, with photo pins where their memories happened",
  "memory-detail": "A memory called Our first date in Rome, with a photo and a note",
  games: "The Games tab: a 47-day streak, today's deep question, and the couple games",
  stats: "Relationship stats: two years and three months together, 822 days, trips, memories and reunions",
  connected: "The screen that says You're connected, with Sam and Alex's avatars joined by a heart",
  "our-story": "Our story: a timeline of every trip, memory and flight they've shared",
} as const;

export type PhoneScreen = keyof typeof PHONE_SCREENS;

export function phoneScreenSrc(screen: PhoneScreen, mode: "light" | "dark") {
  return `/assets/phone-screen/${screen}-${mode}.webp`;
}
