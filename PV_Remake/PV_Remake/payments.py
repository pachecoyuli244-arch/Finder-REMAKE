"""PVFINDER Stripe hosted Checkout. Live-only, server-side pricing, manual fulfillment."""
import json
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

# One-time USD prices. Never trust price, currency, or destination from the browser.
PLANS = {
    "daily": ("24 horas", 300),
    "weekly": ("7 días", 1700),
    "monthly": ("30 días", 3500),
}

def _live_ready(public_url):
    key = os.environ.get("PVFINDER_STRIPE_SECRET_KEY", "")
    parsed = urlparse(public_url or "")
    return (os.environ.get("PVFINDER_STRIPE_ENABLED") == "1"
            and key.startswith("sk_live_") and len(key) > 24
            and parsed.scheme == "https" and bool(parsed.netloc)
            and not parsed.username and not parsed.password
            and not parsed.query and not parsed.fragment)

def status(public_url):
    return {"enabled": _live_ready(public_url),
            "mode": "live" if _live_ready(public_url) else "unavailable",
            "payment_methods": "Tarjeta y Apple Pay cuando sean compatibles"}

def create_checkout(plan, public_url):
    if not isinstance(plan, str) or plan not in PLANS:
        return 400, {"error": "Plan no disponible"}
    if not _live_ready(public_url):
        return 503, {"error": "Pago con tarjeta aún no habilitado"}
    name, cents = PLANS[plan]
    origin = public_url.rstrip("/")
    parameters = [
        ("mode", "payment"),
        ("payment_method_types[0]", "card"),
        ("line_items[0][price_data][currency]", "usd"),
        ("line_items[0][price_data][unit_amount]", str(cents)),
        ("line_items[0][price_data][product_data][name]", "PVFINDER - " + name),
        ("line_items[0][quantity]", "1"),
        ("metadata[product]", "pvfinder_access"),
        ("metadata[plan]", plan),
        ("success_url", origin + "/ventas?retorno_pago=1"),
        ("cancel_url", origin + "/ventas?compra_cancelada=1"),
        ("locale", "es"),
    ]
    request = Request("https://api.stripe.com/v1/checkout/sessions",
                      data=urlencode(parameters).encode("utf-8"),
                      headers={"Authorization": "Bearer " + os.environ["PVFINDER_STRIPE_SECRET_KEY"],
                               "Content-Type": "application/x-www-form-urlencoded"},
                      method="POST")
    try:
        with urlopen(request, timeout=12) as response:
            result = json.load(response)
        target = result.get("url", "")
        parsed = urlparse(target)
        if (parsed.scheme != "https" or not parsed.hostname or
            parsed.hostname != "checkout.stripe.com"):
            return 502, {"error": "Respuesta inesperada del procesador de pagos"}
        return 201, {"ok": True, "url": target,
                     "notice": "La entrega de la key requiere verificación manual"}
    except (HTTPError, URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
        return 502, {"error": "No se pudo iniciar el pago; intenta más tarde"}
