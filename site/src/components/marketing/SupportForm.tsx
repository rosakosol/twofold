"use client";

import { useState } from "react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  MAX_EMAIL_LENGTH,
  MAX_MESSAGE_LENGTH,
  MAX_NAME_LENGTH,
  SUPPORT_CATEGORIES,
  validateSupportRequest,
  type SupportField,
} from "@/lib/validation/support";

type Status = "idle" | "sending" | "success" | "error";

const GENERIC_ERROR = "Something went wrong. Please try again.";

function FieldError({ field, error }: { field: SupportField; error: string | undefined }) {
  if (!error) return null;
  return (
    <p id={`support-${field}-error`} className="field-error">
      {error}
    </p>
  );
}

export function SupportForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState("");
  // One field at fault at a time, the same first-failure order the route uses. Marked on the input
  // itself (aria-invalid, aria-describedby) rather than only in the line under the button.
  const [fieldError, setFieldError] = useState<{ field: SupportField; error: string } | null>(null);
  // The category picker is a Base UI Select rather than a native <select>, so its value
  // isn't in the form's own FormData - it's held here and cleared alongside form.reset().
  const [category, setCategory] = useState<string | null>(null);

  function errorFor(field: SupportField) {
    return fieldError?.field === field ? fieldError.error : undefined;
  }

  function fieldProps(field: SupportField) {
    const error = errorFor(field);
    return {
      "aria-invalid": error ? true : undefined,
      "aria-describedby": error ? `support-${field}-error` : undefined,
    };
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const formData = new FormData(form);
    const payload = {
      name: String(formData.get("name") ?? ""),
      email: String(formData.get("email") ?? ""),
      category: category ?? "",
      message: String(formData.get("message") ?? ""),
      company: String(formData.get("company") ?? ""),
    };

    // The route's own rules, checked before sending, so a mistake is caught without a round trip.
    // The honeypot is left to the route, which pretends success.
    const validation = validateSupportRequest(payload);
    if (!validation.ok && !payload.company) {
      setFieldError({ field: validation.field, error: validation.error });
      setStatus("error");
      setMessage("Check the highlighted field.");
      form.querySelector<HTMLElement>(`#support-${validation.field}`)?.focus();
      return;
    }

    setFieldError(null);
    setStatus("sending");
    setMessage("");
    try {
      const res = await fetch("/api/support", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      // A gateway error page isn't JSON; that is a failure to send, not a parse error to show.
      const data = (await res.json().catch(() => ({}))) as { error?: string; field?: SupportField };
      if (res.ok) {
        setStatus("success");
        setMessage("Message sent - we'll get back to you soon.");
        form.reset();
        setCategory(null);
      } else {
        setStatus("error");
        setMessage(data.error || GENERIC_ERROR);
        if (data.field && data.error) setFieldError({ field: data.field, error: data.error });
      }
    } catch {
      setStatus("error");
      setMessage(GENERIC_ERROR);
    }
  }

  return (
    <form className="support-form" noValidate onSubmit={handleSubmit}>
      <div className="support-field">
        <label htmlFor="support-name">Name</label>
        <input
          id="support-name"
          name="name"
          type="text"
          autoComplete="name"
          placeholder="Your name"
          maxLength={MAX_NAME_LENGTH}
          {...fieldProps("name")}
        />
        <FieldError field="name" error={errorFor("name")} />
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
          maxLength={MAX_EMAIL_LENGTH}
          required
          {...fieldProps("email")}
        />
        <FieldError field="email" error={errorFor("email")} />
      </div>
      <div className="support-field">
        <label htmlFor="support-category">Category</label>
        <Select value={category} onValueChange={(value) => setCategory(value)}>
          <SelectTrigger id="support-category" className="support-select" {...fieldProps("category")}>
            <SelectValue placeholder="Select a category" />
          </SelectTrigger>
          <SelectContent className="support-select-popup">
            {SUPPORT_CATEGORIES.map((option) => (
              <SelectItem key={option} value={option}>
                {option}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <FieldError field="category" error={errorFor("category")} />
      </div>
      <div className="support-field">
        <label htmlFor="support-message">Message</label>
        <textarea
          id="support-message"
          name="message"
          placeholder="What's going on?"
          maxLength={MAX_MESSAGE_LENGTH}
          required
          {...fieldProps("message")}
        />
        <FieldError field="message" error={errorFor("message")} />
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
