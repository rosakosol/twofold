import type { Metadata } from "next";
import { FeedbackBoard } from "./FeedbackBoard";

// A server page so the board can have its own title and description: the board itself is a client
// component, and a "use client" page can't export metadata, so /feedback used to share the home
// page's.
export const metadata: Metadata = {
  title: "Feedback",
  description: "Vote on ideas for Twofold, see what's planned and in progress, or suggest something new.",
  alternates: { canonical: "/feedback" },
};

export default function FeedbackPage() {
  return <FeedbackBoard />;
}
