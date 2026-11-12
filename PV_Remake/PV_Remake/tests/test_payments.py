"""Tests for isolated payment checkout: no network or charge creation."""
import io
import unittest
from unittest.mock import patch
import payments


class CheckoutTests(unittest.TestCase):
    def test_prices_are_server_side_usd_cents(self):
        self.assertEqual(payments.PLANS["daily"][1], 300)
        self.assertEqual(payments.PLANS["weekly"][1], 1700)
        self.assertEqual(payments.PLANS["monthly"][1], 3500)

    def test_disabled_by_default(self):
        with patch.dict("os.environ", {}, clear=True):
            self.assertFalse(payments.status("https://example.com")["enabled"])
            code, response = payments.create_checkout("daily", "https://example.com")
        self.assertEqual(code, 503)
        self.assertNotIn("url", response)

    def test_test_key_cannot_enable_real_checkout(self):
        with patch.dict("os.environ", {
            "PVFINDER_STRIPE_SECRET_KEY": "sk_test_" + "a" * 30,
            "PVFINDER_STRIPE_ENABLED": "1",
        }, clear=True):
            self.assertFalse(payments.status("https://example.com")["enabled"])

    def test_invalid_plan_is_rejected_without_network(self):
        for invalid in (None, "", "other", [], {}, 1):
            code, response = payments.create_checkout(invalid, "https://example.com")
            self.assertEqual(code, 400)
            self.assertIn("error", response)

    def test_live_checkout_uses_authoritative_price(self):
        class Response:
            def __enter__(self):
                return io.BytesIO(b'{"url":"https://checkout.stripe.com/c/pay/example"}')
            def __exit__(self, *args):
                return False
        payloads = []
        def fake_urlopen(request, timeout):
            payloads.append(request.data.decode("utf-8"))
            return Response()
        with patch.dict("os.environ", {
            "PVFINDER_STRIPE_SECRET_KEY": "sk_live_" + "a" * 30,
            "PVFINDER_STRIPE_ENABLED": "1",
        }, clear=True), patch.object(payments, "urlopen", fake_urlopen):
            code, data = payments.create_checkout("weekly", "https://example.com")
        self.assertEqual(code, 201)
        self.assertTrue(data["url"].startswith("https://checkout.stripe.com"))
        self.assertIn("unit_amount%5D=1700", payloads[0])
        self.assertIn("currency%5D=usd", payloads[0])


if __name__ == "__main__":
    unittest.main()
