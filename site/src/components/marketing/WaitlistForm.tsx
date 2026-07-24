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
        setMessage("You're on the list — we'll email you when Android is ready.");
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

  return (
    <form className="waitlist-form" noValidate onSubmit={handleSubmit}>
      <div className="field-row">
        <label className="sr-only" htmlFor="waitlist-email">
          Email address
        </label>
        <input
          id="waitlist-email"
          name="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          placeholder="you@example.com"
          required
        />
        <input className="hp-field" type="text" name="company" tabIndex={-1} autoComplete="off" aria-hidden="true" />
        <button type="submit" className="btn btn-primary" disabled={status === "sending"}>
          {status === "sending" ? "Joining…" : "Join waitlist"}
        </button>
      </div>
      <p
        className="form-status"
        role="status"
        aria-live="polite"
        data-state={status === "success" ? "success" : status === "error" ? "error" : undefined}
      >
        {message}
      </p>
    </form>
  );
}
