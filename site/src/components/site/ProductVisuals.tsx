import type { ReactNode } from "react";
import { Flame, Plane, Check } from "lucide-react";

/*
 * The app's widgets, Live Activity and notification, drawn on the page rather than screenshotted
 * (docs/TWOFOLD_WEBSITE.md, sections 4 and 5). A simulator can capture the app's screens but not a
 * Home Screen widget or the Lock Screen, and these are the visuals the spec places around the
 * phones. They follow the app's own widget designs, with the sample couple's story: Alex in Rome,
 * Sam in Melbourne.
 *
 * Each is a picture of the product, so each is one image to assistive technology: a role="img"
 * with a label saying what it shows, and nothing inside it read out separately.
 */

function Visual({ label, className, children }: { label: string; className: string; children: ReactNode }) {
  return (
    <div role="img" aria-label={label} className={className}>
      {children}
    </div>
  );
}

/** The trip countdown widget, small: coral, "22 days until Alex lands in Melbourne". */
export function CountdownWidget({ className }: { className?: string }) {
  return (
    <Visual label="Trip countdown widget: next reunion in 22 days, until Alex lands in Melbourne" className={["pv-widget pv-countdown", className].filter(Boolean).join(" ")}>
      <span className="pv-widget-label">Next reunion</span>
      <span className="pv-countdown-days">22 days</span>
      <span className="pv-widget-sub">until Alex lands in Melbourne</span>
    </Visual>
  );
}

/** The drawing pad widget, medium: Alex's note on the paper, left before bed in Rome. */
export function DrawingPadWidget({ className }: { className?: string }) {
  return (
    <Visual label="Drawing pad widget: Alex's drawing of a sun and a heart with the words good morning, left at 11:24 pm in Rome" className={["pv-widget pv-drawing", className].filter(Boolean).join(" ")}>
      <div className="pv-drawing-head">
        <span className="pv-avatar pv-avatar-alex" aria-hidden>A</span>
        <span className="pv-drawing-who">From Alex</span>
        <span className="pv-drawing-when">11:24 pm in Rome</span>
      </div>
      <svg className="pv-drawing-paper" viewBox="0 0 320 130" aria-hidden>
        <g fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round">
          {/* a sun */}
          <circle cx="58" cy="62" r="20" />
          <path d="M58 26v-10M58 108v-10M22 62H12M104 62H94M33 37l-7-7M90 94l-7-7M33 87l-7 7M90 30l-7 7" />
          {/* a heart */}
          <path className="pv-drawing-heart" d="M276 104c-10-8-16-14-12-20 3-5 10-4 12 2 2-6 9-7 12-2 4 6-2 12-12 20z" />
        </g>
        <text className="pv-drawing-words" x="124" y="74">good morning</text>
      </svg>
    </Visual>
  );
}

/** Today's question widget, on the daily-question gradient. */
export function DailyQuestionWidget({ className }: { className?: string }) {
  return (
    <Visual label="Today's question widget: What's a small thing I do that makes you feel loved? Both of you have answered." className={["pv-widget pv-daily", className].filter(Boolean).join(" ")}>
      <span className="pv-widget-label">Today&rsquo;s question</span>
      <span className="pv-daily-question">What&rsquo;s a small thing I do that makes you feel loved?</span>
      <span className="pv-daily-foot">
        <Check aria-hidden /> Both answered
      </span>
    </Visual>
  );
}

/** The streak row from the Games tab: a coral flame, 47 days, both answered today. */
export function StreakRow({ className }: { className?: string }) {
  return (
    <Visual label="A 47-day streak, both answered today" className={["pv-streak", className].filter(Boolean).join(" ")}>
      <span className="pv-streak-flame">
        <Flame aria-hidden />
      </span>
      <span className="pv-streak-text">
        <strong>47-day streak</strong>
        <span>Both answered today</span>
      </span>
    </Visual>
  );
}

/** Alex's flight as a Live Activity on the Lock Screen: Doha to Melbourne, 86% of the way. */
export function FlightLiveActivity({ className }: { className?: string }) {
  return (
    <Visual label="Live Activity for flight QR904 from Doha to Melbourne: 86% complete, lands in 1 hour 47 minutes" className={["pv-live", className].filter(Boolean).join(" ")}>
      <div className="pv-live-head">
        <span className="pv-avatar pv-avatar-alex" aria-hidden>A</span>
        <span className="pv-live-title">
          <strong>Alex is on the way</strong>
          <span>Qatar Airways QR904</span>
        </span>
        <span className="pv-live-eta">
          <strong>1h 47m</strong>
          <span>to land</span>
        </span>
      </div>
      <div className="pv-live-route">
        <span className="pv-live-code">DOH</span>
        <span className="pv-live-track">
          <span className="pv-live-progress" />
          <Plane className="pv-live-plane" aria-hidden />
        </span>
        <span className="pv-live-code">MEL</span>
      </div>
      <div className="pv-live-foot">
        <span>Departed 8:05 pm</span>
        <span>Gate 9 · Belt 4</span>
      </div>
    </Visual>
  );
}

/** An iOS notification, on frosted dark glass. */
export function AppNotification({ title, body, className }: { title: string; body: string; className?: string }) {
  return (
    <Visual label={`Notification from Twofold, now: ${title}. ${body}`} className={["pv-notification", className].filter(Boolean).join(" ")}>
      {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size app icon */}
      <img src="/assets/app-icon.png" alt="" width={38} height={38} />
      <span className="pv-notification-text">
        <strong>{title}</strong>
        <span>{body}</span>
      </span>
      <span className="pv-notification-time">now</span>
    </Visual>
  );
}

/** A "Who's more likely to" card from the game: the question on the coral gradient, and the two
 *  of them to pick between. */
export function WhosMoreLikelyCard({ className }: { className?: string }) {
  return (
    <Visual label="A Who's more likely to card: who's more likely to plan a surprise trip, Alex or Sam?" className={["pv-likely", className].filter(Boolean).join(" ")}>
      <span className="pv-widget-label">Who&rsquo;s more likely to</span>
      <span className="pv-likely-question">plan a surprise trip without telling the other?</span>
      <span className="pv-likely-choices">
        <span className="pv-likely-choice">
          <span className="pv-avatar pv-avatar-alex">A</span>Alex
        </span>
        <span className="pv-likely-choice">
          <span className="pv-avatar pv-avatar-sam">S</span>Sam
        </span>
      </span>
    </Visual>
  );
}

/** The flight widget, small: Alex's flight on the flight gradient. */
export function FlightWidget({ className }: { className?: string }) {
  return (
    <Visual label="Flight widget: Alex's flight QR904 from Doha to Melbourne, landing at 9:38 pm" className={["pv-widget pv-flight", className].filter(Boolean).join(" ")}>
      <span className="pv-widget-label">
        <Plane aria-hidden /> QR904
      </span>
      <span className="pv-flight-route">DOH &rarr; MEL</span>
      <span className="pv-widget-sub">Alex lands at 9:38 pm</span>
    </Visual>
  );
}

/** The Lock Screen, drawn: the time, the flight's Live Activity and two widgets. Goes inside the
 *  phone frame in place of a screenshot, since the Lock Screen cannot be captured from the app. */
export function LockScreen() {
  return (
    <div role="img" aria-label="Lock Screen with a Live Activity tracking Alex's flight, and the trip countdown and distance widgets" className="pv-lock">
      <span className="pv-lock-date">Tuesday 6 October</span>
      <span className="pv-lock-time">9:41</span>
      <span className="pv-lock-widgets">
        <span className="pv-lock-widget">
          <strong>22 days</strong>
          <span>to Alex</span>
        </span>
        <span className="pv-lock-widget">
          <strong>15,966 km</strong>
          <span>apart</span>
        </span>
      </span>
      <FlightLiveActivity className="pv-lock-live" />
    </div>
  );
}

/** The printed Relationship Record's cover. */
export function KeepsakeCover({ className }: { className?: string }) {
  return (
    <Visual label="The printed Relationship Record: Our Relationship Record, Alex and Sam, 48 pages, PDF" className={["pv-keepsake", className].filter(Boolean).join(" ")}>
      {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
      <img src="/assets/globe-heart.png" alt="" width={40} height={40} />
      <span className="pv-keepsake-title">Our Relationship Record</span>
      <span className="pv-keepsake-names">Alex and Sam</span>
      <span className="pv-keepsake-meta">48 pages, PDF</span>
    </Visual>
  );
}
