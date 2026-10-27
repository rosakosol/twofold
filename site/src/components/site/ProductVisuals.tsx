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

/** The trip countdown widget, small: coral, 22 days until Alex's trip from Rome to Melbourne. */
export function CountdownWidget({ className }: { className?: string }) {
  return (
    <Visual label="Trip countdown widget: next reunion in 22 days, when Alex flies from Rome to Melbourne" className={["pv-widget pv-countdown", className].filter(Boolean).join(" ")}>
      <span className="pv-widget-label">Next reunion</span>
      <span className="pv-countdown-days">22 days</span>
      <span className="pv-widget-sub">until Alex flies to Melbourne</span>
    </Visual>
  );
}

/** The drawing pad widget, medium: Alex's note on the paper, left before bed in Rome. */
export function DrawingPadWidget({ className }: { className?: string }) {
  return (
    <Visual label="Drawing pad widget: Alex's handwritten note, missing you, with a heart, left at 11:24 pm in Rome" className={["pv-widget pv-drawing", className].filter(Boolean).join(" ")}>
      <div className="pv-drawing-head">
        <span className="pv-avatar pv-avatar-alex is-photo" aria-hidden>A</span>
        <span className="pv-drawing-who">From Alex</span>
        <span className="pv-drawing-when">11:24 pm in Rome</span>
      </div>
      {/* Alex's real drawing from the app's Drawing Pad widget, white paper made transparent. */}
      {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size drawing */}
      <img className="pv-drawing-paper" src="/assets/drawing-missing-you.webp" alt="" width={142} height={242} />
    </Visual>
  );
}

/** Today's deep question widget, on the daily-question gradient: Alex has answered, it's Sam's turn. */
export function DailyQuestionWidget({ className }: { className?: string }) {
  return (
    <Visual label="Today's deep question widget: What's a criticism that changed how you work? Alex has answered." className={["pv-widget pv-daily", className].filter(Boolean).join(" ")}>
      <span className="pv-widget-label">Today&rsquo;s deep question</span>
      <span className="pv-daily-question">What&rsquo;s a criticism that changed how you work?</span>
      <span className="pv-daily-foot">
        <Check aria-hidden /> Alex answered
      </span>
    </Visual>
  );
}

/** The streak row from the Games tab: a coral flame, and no streak yet. */
export function StreakRow({ className }: { className?: string }) {
  return (
    <Visual label="Start a streak: answer today's question together" className={["pv-streak", className].filter(Boolean).join(" ")}>
      <span className="pv-streak-flame">
        <Flame aria-hidden />
      </span>
      <span className="pv-streak-text">
        <strong>Start a streak</strong>
        <span>Answer today&rsquo;s question together</span>
      </span>
    </Visual>
  );
}

/** Alex's flight as a Live Activity on the Lock Screen: Emirates EK96, Rome to Dubai, 86% of the way. */
export function FlightLiveActivity({ className }: { className?: string }) {
  return (
    <Visual label="Live Activity for Alex's Emirates flight EK96 from Rome to Dubai: 55 minutes to landing, left Rome at 10:10 pm, lands at 5:50 am" className={["pv-live", className].filter(Boolean).join(" ")}>
      <div className="pv-live-head">
        <span className="pv-avatar pv-avatar-alex is-photo" aria-hidden>A</span>
        <span className="pv-live-title">
          <strong>Alex is on the way</strong>
          <span>EK96 to Dubai</span>
        </span>
        <span className="pv-live-eta">
          <strong>55m</strong>
          <span>to landing</span>
        </span>
      </div>
      <div className="pv-live-route">
        <span className="pv-live-track">
          <span className="pv-live-progress" />
          <span className="pv-live-knob">
            <Plane className="pv-live-plane" aria-hidden />
          </span>
        </span>
      </div>
      <div className="pv-live-foot">
        <span>
          <span className="pv-live-code">FCO</span> 10:10 pm
        </span>
        <span>
          <span className="pv-live-code">DXB</span> 5:50 am
        </span>
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
          <span className="pv-avatar pv-avatar-alex is-photo">A</span>Alex
        </span>
        <span className="pv-likely-choice">
          <span className="pv-avatar pv-avatar-sam is-photo">S</span>Sam
        </span>
      </span>
    </Visual>
  );
}

/**
 * The flight widget, small, after the app's own (LiveActivities/FlightTrackingWidget.swift), in
 * the three states it shows EK96 in:
 * - `partner`: Alex's flight before departure, his photo in the corner.
 * - `mine`: your own flight before departure, the airline's badge in place of a photo.
 * - `in-air`: Alex's flight under way, the time to landing over a progress line.
 */
export function FlightWidget({
  state = "in-air",
  className,
}: {
  state?: "partner" | "mine" | "in-air";
  className?: string;
}) {
  const inAir = state === "in-air";
  const label = inAir
    ? "Flight widget: Alex's flight EK96 from Rome to Dubai, 86% complete, lands in 55 minutes"
    : `Flight widget: ${state === "mine" ? "your" : "Alex's"} flight EK96 from Rome to Dubai, departs in 24 days 8 hours`;
  return (
    <Visual label={label} className={["pv-widget pv-flight", className].filter(Boolean).join(" ")}>
      <span className="pv-flight-head">
        {state === "mine" ? (
          <span className="pv-flight-airline" aria-hidden>
            EK
          </span>
        ) : (
          <span className="pv-avatar pv-avatar-alex is-photo" aria-hidden>
            A
          </span>
        )}
        EK96
      </span>
      <span className="pv-flight-when">
        <span>{inAir ? "Lands in" : "Departs in"}</span>
        <strong>{inAir ? "55m" : "24d 8h"}</strong>
      </span>
      {inAir ? (
        <span className="pv-flight-rail" aria-hidden>
          <span className="pv-flight-rail-done" />
          <span className="pv-flight-rail-marker">
            <Plane />
          </span>
        </span>
      ) : (
        <span className="pv-flight-route">
          FCO <Plane aria-hidden /> DXB
        </span>
      )}
    </Visual>
  );
}

/** The printed Relationship Record's cover. */
export function KeepsakeCover({ className }: { className?: string }) {
  return (
    <Visual label="The printed Relationship Record: Our Relationship Record, Alex and Sam, as a PDF or Word document" className={["pv-keepsake", className].filter(Boolean).join(" ")}>
      {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
      <img src="/assets/globe-heart.png" alt="" width={40} height={40} />
      <span className="pv-keepsake-title">Our Relationship Record</span>
      <span className="pv-keepsake-names">Alex and Sam</span>
      <span className="pv-keepsake-meta">PDF or Word</span>
    </Visual>
  );
}
