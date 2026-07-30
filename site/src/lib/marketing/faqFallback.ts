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
      "Plus covers everything most couples need - unlimited trips and memories, up to 5 tracked flights a month, and 500+ questions and games. Premium adds more flight tracking, 2000+ questions and games, and exclusive Home Screen and Lock Screen widgets.",
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
    question: "What happens to shared data if we disconnect?",
    answer:
      "Removing a partner archives your shared data rather than deleting it immediately, so either of you can permanently delete it afterward from Settings.",
  },
  {
    category: "privacy",
    order: 4,
    question: "What happens to our shared data if I delete my account?",
    answer:
      "By default it stays with your partner - shared trips, memories, and photos are their history too, so deleting your account doesn't erase their side of it. Because you won't be able to sign back in afterwards, the delete screen offers to permanently delete the shared data at the same time. That removes it for both of you and can't be undone. If you skip it, only your former partner can delete it from then on.",
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
