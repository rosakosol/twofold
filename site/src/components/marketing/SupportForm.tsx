"use client";

import { useState } from "react";

type Status = "idle" | "sending" | "success" | "error";

// Same category list as the iOS app's own support form (HelpService.SupportRequestCategory) —
// keep the two in sync if categories ever change there.
const CATEGORIES = [
  "Account & Subscription",
  "Bug Report",
  "Flight Tracking",
  "Trips & Memories",
  "Game Issue",
  "Feature Request",
  "Feedback",
  "Other",
] as const;

export function SupportForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState("");

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const formData = new FormData(form);
    const payload = {
      name: String(formData.get("name") ?? ""),
      email: String(formData.get("email") ?? ""),
      category: String(formData.get("category") ?? ""),
      message: String(formData.get("message") ?? ""),
      company: String(formData.get("company") ?? ""),
    };

    setStatus("sending");
    setMessage("");
    try {
      const res = await fetch("/api/support", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (res.ok) {
        setStatus("success");
        setMessage("Message sent — we'll get back to you soon.");
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
    <form className="support-form" noValidate onSubmit={handleSubmit}>
      <div className="support-field">
        <label htmlFor="support-name">Name</label>
        <input id="support-name" name="name" type="text" autoComplete="name" placeholder="Your name" />
      </div>
      <div className="support-field">
        <label htmlFor="support-email">Email</label>
        <input
          id="support-email"
          name="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          placeholder="yourname@email.com"
          required
        />
      </div>
      <div className="support-field">
        <label htmlFor="support-category">Category</label>
        <select id="support-category" name="category" required defaultValue="">
          <option value="" disabled>
            Select a category
          </option>
          {CATEGORIES.map((category) => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </select>
      </div>
      <div className="support-field">
        <label htmlFor="support-message">Message</label>
        <textarea id="support-message" name="message" placeholder="What's going on?" required />
      </div>
      <input className="hp-field" type="text" name="company" tabIndex={-1} autoComplete="off" aria-hidden="true" />
      <button type="submit" className="btn btn-primary" disabled={status === "sending"}>
        {status === "sending" ? "Sending…" : "Send message"}
      </button>
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
