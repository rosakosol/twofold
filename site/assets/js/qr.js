// Renders a small App Store QR code into any element with [data-qr]. Desktop-only
// part of the web2app funnel — mobile visitors already get the direct App Store button.

import { APP_STORE_URL } from "/assets/js/config.js";

async function renderQr() {
  const targets = document.querySelectorAll("[data-qr]");
  if (!targets.length) return;

  try {
    const { default: qrcode } = await import("https://esm.sh/qrcode-generator@2.0.4");
    const qr = qrcode(0, "M");
    qr.addData(APP_STORE_URL + "?ref=web_qr");
    qr.make();
    targets.forEach((el) => {
      el.innerHTML = qr.createSvgTag(4, 2);
    });
  } catch (err) {
    console.warn("[twofold] QR render failed", err);
    targets.forEach((el) => el.closest(".qr-card")?.style.setProperty("display", "none"));
  }
}

renderQr();
