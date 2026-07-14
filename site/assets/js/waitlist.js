const form = document.getElementById("waitlist-form");
if (form) {
  const status = document.getElementById("waitlist-status");
  const button = form.querySelector("button[type=submit]");

  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = form.email.value.trim();
    const honeypot = form.company.value;

    if (!email) return;

    button.disabled = true;
    status.dataset.state = "";
    status.textContent = "Joining…";

    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, company: honeypot }),
      });

      const data = await response.json().catch(() => ({}));

      if (response.ok) {
        status.dataset.state = "success";
        status.textContent = "You're on the list! Check your inbox for a confirmation.";
        form.reset();
      } else if (response.status === 409) {
        status.dataset.state = "success";
        status.textContent = "You're already on the list — we'll be in touch.";
        form.reset();
      } else {
        status.dataset.state = "error";
        status.textContent = data.error || "Something went wrong. Please try again.";
      }
    } catch (error) {
      status.dataset.state = "error";
      status.textContent = "Something went wrong. Please try again.";
    } finally {
      button.disabled = false;
    }
  });
}
