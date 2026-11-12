"use strict";

// PVFinder: public plan-selection UX only. No payment credentials here.
// Actual payment verification and key delivery are performed manually by owner.
const dialog = document.getElementById("purchase-dialog");
const selectedTitle = document.getElementById("purchase-title");
const messageBox = document.getElementById("request-message");
const copyButton = document.getElementById("copy-request");
const paypalPayLink = document.getElementById("paypal-pay-link");
const stripePayButton = document.getElementById("stripe-checkout");
let selectedPlan = null;
if (stripePayButton) {
  fetch("/api/payments/status", {cache:"no-store"})
    .then(r => r.ok ? r.json() : null)
    .then(data => { stripePayButton.hidden = !data?.enabled; })
    .catch(() => {stripePayButton.hidden = true;});
}
const afterPayment = document.getElementById("after-payment");
const paypalMeBase = "https://paypal.me/PVFINSER0ficial";
const mpClabeElement = document.getElementById("mp-clabe");
const closeButton = document.getElementById("close-dialog");
const toast = document.getElementById("toast");
const brand = document.getElementById("brand");
const footerBrand = document.getElementById("footerBrand");
const year = document.getElementById("year");

if (brand) brand.textContent = "PVFINDER";
if (footerBrand) footerBrand.textContent = "PVFinder";
if (year) year.textContent = String(new Date().getFullYear());

let toastTimeout;
function notify(message) {
  if (!toast) return;
  toast.textContent = message;
  toast.style.display = "block";
  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => {toast.style.display = "none";}, 4400);
}

document.querySelectorAll("button[data-plan]").forEach(button => {
  button.addEventListener("click", () => {
    selectedPlan = button.dataset.plan;
    const card = button.closest(".card");
    const label = card?.querySelector(".plan-name")?.textContent.trim();
    const amount = Number(card?.querySelector(".plan-amount")?.textContent.trim().replace(/^\$/, ""));
    if (!label || !Number.isFinite(amount) || amount <= 0 || !dialog || !messageBox) return;
    const price = "$" + amount.toFixed(2).replace(/\.00$/, "") + " USD";
    selectedTitle.textContent = label + " · " + price;
    if (afterPayment) afterPayment.hidden = true;
    if (paypalPayLink) {
      // PayPal.Me supports the amount plus currency code (e.g. /7USD).
      // Payments, successful transactions and customer identity are NOT verified here.
      paypalPayLink.href = paypalMeBase + "/" + String(amount) + "USD";
      paypalPayLink.textContent = "💳 Pagar " + price + " con PayPal";
    }
    messageBox.value =
      "Hola, quiero comprar acceso a PVFINDER.\n" +
      "Plan: " + label + "\n" +
      "Precio: " + price + "\n\n" +
      "Método: PayPal en USD o SPEI en MXN según lo que elija. Enviaré mi comprobante cuando complete el pago. " +
      "Entiendo que mi key se entrega manualmente después de verificar el dinero recibido.";
    dialog.showModal();
  });
});

if (stripePayButton) {
  stripePayButton.addEventListener("click", async () => {
    if (!selectedPlan || stripePayButton.disabled) return;
    stripePayButton.disabled = true;
    stripePayButton.textContent = "Abriendo pago seguro…";
    try {
      const response = await fetch("/api/payments/checkout", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({plan:selectedPlan})
      });
      const payload = await response.json();
      if (!response.ok || !payload?.url) throw new Error("No disponible");
      const link = new URL(payload.url);
      if (link.protocol !== "https:" || link.hostname !== "checkout.stripe.com")
        throw new Error("Destino no permitido");
      window.location.assign(link.href);
    } catch (_) {
      notify("No se pudo abrir el pago con tarjeta. Puedes usar PayPal.");
      stripePayButton.disabled = false;
      stripePayButton.textContent = "💳 Mastercard / Visa / Apple Pay (si está disponible)";
    }
  });
}
if (paypalPayLink && afterPayment) {
  // We can tell that the user opened PayPal, NOT that payment succeeded.
  paypalPayLink.addEventListener("click", () => {
    afterPayment.hidden = false;
  });
}

if (closeButton) closeButton.addEventListener("click", () => dialog.close());

if (dialog) {
  dialog.addEventListener("click", e => {if (e.target === dialog) dialog.close();});
}

if (copyButton) {
  copyButton.addEventListener("click", async () => {
    const value = messageBox?.value || "";
    if (!value) return;
    let copied = false;
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(value);
        copied = true;
      }
    } catch (_) { /* Provide selection fallback. */ }
    if (!copied && messageBox) {
      messageBox.focus();
      messageBox.select();
      try { copied = document.execCommand("copy"); } catch (_) {}
    }
    notify(copied ?
      "Solicitud copiada. Pégala en tu ticket privado de Discord." :
      "Selecciona y copia el mensaje para enviarlo en tu ticket.");
  });
}

async function copyMpClabe() {
  const clabe = mpClabeElement?.textContent?.trim() || "";
  if (!/^\d{18}$/.test(clabe)) return notify("CLABE no disponible.");
  let copied = false;
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(clabe);
      copied = true;
    }
  } catch (_) {}
  if (!copied) {
    const input = document.createElement("textarea");
    input.value = clabe;
    input.setAttribute("readonly", "");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.appendChild(input);
    input.select();
    try { copied = document.execCommand("copy"); } catch (_) {}
    input.remove();
  }
  notify(copied ? "CLABE copiada. Confirma el importe en MXN y envía comprobante por ticket." : "Selecciona la CLABE para copiarla.");
  if (copied && dialog?.open && afterPayment) afterPayment.hidden = false;
}
document.querySelectorAll(".copy-clabe").forEach(button => button.addEventListener("click", copyMpClabe));
