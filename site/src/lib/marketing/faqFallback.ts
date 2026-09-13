// Cold-start fallback for the FAQ page — rendered only if getFaqEntries() (Supabase) fails
// entirely, same "never blank the page" fail-soft pattern the old cms-faq.js used.
//
// Supabase `faq_entries` is the source of truth, and it feeds the iOS app's Support screen as
// well as this page — so this file is a MIRROR, not an independent copy. Text is transcribed
// verbatim from the live rows so the failure path can't quietly show different answers to the
// app's. Re-check it whenever entries are edited through Studio → FAQ; `node -e` against the
// table is the quickest way to diff the two.
//
// House style for FAQ copy is a plain hyphen, never an em or en dash — the live rows and these
// mirrored strings both follow it. (Comments like this one aren't copy, so they don't.)
//
// Categories are transcribed from the live `category` column rather than being an independent
// taxonomy, for the same reason.
export interface FaqFallbackItem {
  category: "getting-started" | "subscriptions" | "privacy" | "flights" | "trips";
  order: number;
  question: string;
  answer: string;
}

export const FAQ_FALLBACK: FaqFallbackItem[] = [
  {
    category: "getting-started",
    order: 1,
    question: "What is Twofold?",
    answer:
      "Twofold is a native iOS app built for long-distance couples. It turns your relationship into a living map - track each other's flights in real time, watch the distance between you close, and save memories to the places they happened, all on a shared 3D globe.",
  },
  {
    category: "getting-started",
    order: 2,
    question: "What platforms is Twofold available on?",
    answer:
      "Twofold is available now on iOS. We're building the Android version next - join the waitlist at twofoldapp.com.au and we'll email you the moment it's ready.",
  },
  {
    category: "getting-started",
    order: 3,
    question: "How do I connect with my partner?",
    answer:
      "During onboarding you'll get a personal invite link. Send it to your partner and once they accept, your accounts are connected - trips, flights, memories, and games become shared from that point on.",
  },
  {
    category: "subscriptions",
    order: 1,
    question: "What's the difference between Plus and Premium?",
    answer:
      "Plus covers everything most couples need - unlimited trips and memories, 2 live-tracked flights a month, 500+ questions, and Sudoku, Word Guess, Word Search and Connect 4. Premium adds 5 live-tracked flights a month, 2000+ questions including premium decks, Chess, Sudoku on Hard and Expert, every Word Search theme, unlimited Word Guess, flight delay analysis, a streak repair each month, the Smart Rotating widget, and the Relationship Record - your whole history as one printable document. Either way you can save as many flights as you like - the limit is on live tracking, so a flight beyond it still appears in your trips and your Passport, it just will not send you live updates.",
  },
  {
    category: "subscriptions",
    order: 2,
    question: "Can I subscribe on the web instead of in the app?",
    answer:
      "Yes. You can subscribe right from our pricing page using Sign in with Apple - it unlocks your account the same way an in-app purchase does. Open the app afterward and sign in with the same Apple ID to see it active.",
  },
  {
    category: "subscriptions",
    order: 3,
    question: "How do I cancel or manage my subscription?",
    answer:
      "If you subscribed in the app, manage or cancel it from your device's Settings → Apple ID → Subscriptions. If you subscribed on the web, manage it from your account on the pricing page, or email hello@twofoldapp.com.au and we'll sort it out. Either way, you keep access until the end of the period you've already paid for.",
  },
  {
    category: "subscriptions",
    order: 4,
    question: "Does one subscription cover both partners?",
    answer:
      "Yes, once you're connected, either partner's active Plus or Premium subscription unlocks the full experience for both of you. Only one of you needs to subscribe.",
  },
  {
    category: "subscriptions",
    order: 5,
    question: "Is my payment secure?",
    answer:
      "Web purchases are processed by Stripe via RevenueCat. Twofold never sees or stores your card details. In-app purchases go through Apple's App Store billing.",
  },
  {
    category: "subscriptions",
    order: 6,
    question: "My partner and I are on different plans - is that normal?",
    answer:
      "No - a couple shares one subscription. If you're seeing different access levels, try reopening the app on both devices; if it persists, reach out via support@twofoldapp.com.au and we'll sort it out.",
  },
  {
    category: "privacy",
    order: 1,
    question: "Who can see my trips and location?",
    answer:
      "Only the partner you're connected to. Twofold isn't a public or social app, and your travel information is never shared beyond your relationship. See our Privacy Policy for details.",
  },
  {
    category: "privacy",
    order: 2,
    question: "How does Twofold use my location?",
    answer:
      "Twofold never has access to your location in the background or while the app is closed, and it never follows your exact position. If you allow location access, it checks which city you're in when you open the app - at most once an hour - and updates your home city if you've moved, so your partner sees where you are without you having to remember to change it. Each check resolves to a city and nothing finer, and a new city replaces the last, so there's no trail of where you've been. You can decline location access and set your city by hand instead.",
  },
  {
    category: "privacy",
    order: 3,
    question: "What happens to a flight email I share with Twofold?",
    answer:
      "You can share a booking confirmation or boarding pass into Twofold instead of typing a flight in by hand. The app holds it on your device until you open it and ask for it to be read. If you go ahead, the email's subject and text - and, when those are not enough, text pulled from an attached PDF - are sent to OpenAI, which picks out the flight number, airports and times and sends them back. Only what you shared is sent, only at the moment you ask, and OpenAI does not use it to train its models. Close the screen without confirming and nothing leaves your phone. You can always add a flight by hand instead.",
  },
  {
    category: "privacy",
    order: 4,
    question: "How do I report or block someone?",
    answer:
      "If someone sends you something abusive, or is using Twofold to harm or monitor you, tell us. \"Report Abuse\" is on a connection request before you accept it, and on your partner in Settings -> Disconnect Partner; you can also email hello@twofoldapp.com.au. We aim to respond within 48 hours, and we never tell the person that you reported them. You can block someone whether or not you report them: blocking a request stops them sending another, and blocking a partner disconnects you first. Either way they are not told and cannot reach you again. What the two of you shared is archived as normal and deleted on the usual 90-day timer - blocking does not delete it sooner or keep it longer.",
  },
  {
    category: "privacy",
    order: 5,
    question: "Can I download a copy of my data?",
    answer:
      "Yes, on any plan and at any time. Go to Settings -> Help -> Export your data. You choose what to include - trips, memories and their photos, flights, games - and whether you want spreadsheets (CSV, which open in Numbers, Excel or Google Sheets) or a data file (JSON, for moving your information somewhere else). Photos come out as ordinary image files. Large exports download the photos as they go, so they are best done on Wi-Fi. If a relationship has ended, the same export is on each archive in Settings -> Archived Data, and is worth doing before its 90 days are up. The Relationship Record - your story written out as a PDF or Word document to keep or print - is a separate, Premium feature, and is not part of a data export.",
  },
  {
    category: "privacy",
    order: 6,
    question: "What happens to shared data if we disconnect?",
    answer:
      "Removing a partner archives your shared data rather than deleting it. Your trips, memories, photos, flights and games all stay readable to both of you in Settings -> Archived Data, but neither of you can add to them or change them any more. An archive is kept for 90 days and is then permanently deleted, automatically, for both of you - the exact date is shown on the archive itself. Neither partner can bring that date forward or push it back. If you reconnect with the same partner inside those 90 days, you will be offered your shared history back - as long as you both still have your accounts, since an archive belongs to the two accounts that made it and a deleted one cannot be signed into again. You can also hide an archive from your own list at any time: that changes only your view and deletes nothing for either of you. If you want to keep what is in an archive, export it before the 90 days are up - you will get your trips, memories, flights and games as files you can open anywhere, with the photos alongside them.",
  },
  {
    category: "privacy",
    order: 7,
    question: "What happens to our shared data if I delete my account?",
    answer:
      "It stays with your partner. Shared trips, memories and photos are their history too, so deleting your account does not erase their side of it. Deleting your account does end your connection, and that starts the same 90-day clock as removing a partner: the shared history is permanently deleted for both of you once it runs out. There is no way for either of you to delete it sooner - and unlike simply removing a partner, getting back together later cannot bring it back, because an archive is tied to the two accounts that made it and yours will no longer exist. Because you will not be able to sign back in afterwards, export anything you want to keep before you delete your account - everything that is yours alone (your name, your photo, your login) is removed straight away and cannot be recovered.",
  },
  {
    category: "flights",
    order: 1,
    question: "Why isn't my flight showing live tracking yet?",
    answer:
      "A flight added more than a couple of days before departure is added right away, but live tracking (position, gate, delays) only starts once the flight provider assigns it a trackable instance - usually a few days before departure. It switches on automatically, no need to re-add it.",
  },
  {
    category: "flights",
    order: 2,
    question: "Can my partner see the flights I track?",
    answer:
      "Yes, by default a tracked flight is shared with your partner - they'll see the same live status and can get their own notifications. You can keep a flight private to yourself when adding it.",
  },
  {
    category: "trips",
    order: 1,
    question: "What's the difference between a Trip and a Flight?",
    answer:
      "A Trip is the overall journey - dates, destination, who's going - and can have one or more Flights and Memories linked to it. A Flight is a specific tracked flight; a Memory is a photo/note tied to a place and date. Neither requires the other.",
  },
];

export const FAQ_CATEGORY_LABELS: Record<FaqFallbackItem["category"], string> = {
  "getting-started": "Getting started",
  subscriptions: "Subscriptions & billing",
  privacy: "Privacy & data",
  flights: "Flight Tracking",
  trips: "Trips & Memories",
};

/** Group order for the fallback render — matches how the live rows' sort_order groups them.
 *  Exported so the page doesn't keep its own copy of the list and quietly drop a category. */
export const FAQ_FALLBACK_CATEGORY_ORDER = [
  "getting-started",
  "subscriptions",
  "privacy",
  "flights",
  "trips",
] as const satisfies readonly FaqFallbackItem["category"][];
