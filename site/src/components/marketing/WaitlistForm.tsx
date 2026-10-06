"use client";

import { useState } from "react";

type Status = "idle" | "sending" | "success" | "error";

export function WaitlistForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState("");

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const formData = new FormData(form);
    const email = String(formData.get("email") ?? "");
    const company = String(formData.get("company") ?? "");

    setStatus("sending");
    setMessage("");
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, company }),
      });
      const data = await res.json();
      if (res.ok) {
        setStatus("success");
        setMessage("You're on the list - we'll email you when Android is ready.");
        form.reset();
      } else if (res.status === 409) {
        setStatus("success");
        setMessage("You're already on the list.");
        form.reset();
      } else {
        setStatus("error");
        setMessage(data.error || "Something went wrong. Please try again.");
      }
    } catch {
      setStatus("error");
      setMessage("Something went wrong. Please try again.");
    }
  }

  const errorId = "waitlist-status";
  return (
    <form className="waitlist-form" noValidate onSubmit={handleSubmit}>
      <div className="field">
        <label className="field-label" htmlFor="waitlist-email">
          Email address
        </label>
        <div className="waitlist-row">
          <input
            id="waitlist-email"
            className="input"
            name="email"
            type="email"
            inputMode="email"
            autoComplete="email"
            placeholder="yourname@email.com"
            required
            aria-invalid={status === "error" ? true : undefined}
            aria-describedby={message ? errorId : undefined}
          />
          <button type="submit" className="btn btn-primary" disabled={status === "sending"}>
            {status === "sending" ? "Joining…" : "Join waitlist"}
          </button>
        </div>
      </div>
      {/* A honeypot: hidden from people and assistive technology, filled in by bots. */}
      <input className="hp-field" type="text" name="company" tabIndex={-1} autoComplete="off" aria-hidden="true" />
      <p
        id={errorId}
        className={status === "error" ? "field-error" : "field-hint"}
        role="status"
        aria-live="polite"
      >
        {message}
      </p>
    </form>
  );
}
