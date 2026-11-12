"""Public site editor: validation, persistence, roles and safe defaults."""
import sqlite3
import threading
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import site_content

class FakeHandler:
    client_address = ("127.0.0.1", 0)
    def __init__(self, role="coowner"):
        self.role = role
    def respond(self, status, payload):
        return status, payload
    def session(self):
        return {"role": self.role}

class SiteContentTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        site_content.install(self.db)
        self.clock = 1000

    def tearDown(self):
        self.db.close()

    def write(self, values, role="coowner"):
        return site_content.handle_write(
            FakeHandler(role), {"values": values}, self.db, self.lock,
            lambda: self.clock, role, lambda *args: True
        )

    def test_defaults_and_edit_are_persistent(self):
        self.assertEqual(site_content.snapshot(self.db, self.lock)["values"]["plan_weekly_price"], 12)
        status, result = self.write({"plan_weekly_price": 13.50, "home_title_first": "Tu nuevo radar"})
        self.assertEqual(status, 200)
        self.assertEqual(result["values"]["plan_weekly_price"], 13.5)
        self.assertEqual(site_content.snapshot(self.db, self.lock)["values"]["home_title_first"], "Tu nuevo radar")
        count = self.db.execute("SELECT count(*) FROM site_edit_log").fetchone()[0]
        self.assertEqual(count, 1)

    def test_reject_unknown_and_invalid_fields_atomically(self):
        self.assertEqual(self.write({"plan_weekly_price": 0})[0], 400)
        self.assertEqual(self.write({"theme_primary": "javascript:alert(1)"})[0], 400)
        self.assertEqual(self.write({"sales_discord_link": "https://discord.com.evil.com/fake"})[0], 400)
        self.assertEqual(self.write({"home_title_first": "Valid", "malicious_html": "<script>"})[0], 400)
        self.assertEqual(site_content.snapshot(self.db, self.lock)["values"]["home_title_first"], "Tu radar.")

    def test_reset_requires_admin(self):
        self.write({"home_title_first": "Nuevo"})
        handler = FakeHandler("coowner")
        status, _ = site_content.handle_write(handler, {"action":"reset"}, self.db, self.lock,
                                              lambda: self.clock, "coowner", lambda *args: True)
        self.assertEqual(status, 403)
        self.assertEqual(site_content.snapshot(self.db, self.lock)["values"]["home_title_first"], "Nuevo")
        handler = FakeHandler("admin")
        status, _ = site_content.handle_write(handler, {"action":"reset"}, self.db, self.lock,
                                              lambda: self.clock, "admin", lambda *args: True)
        self.assertEqual(status, 200)
        self.assertEqual(site_content.snapshot(self.db, self.lock)["values"]["home_title_first"], "Tu radar.")

    def test_no_html_injection_or_non_discord_redirects(self):
        status, result = self.write({"sales_intro": '<script>alert("x")</script>'})
        self.assertEqual(status, 200)
        self.assertEqual(result["values"]["sales_intro"], '<script>alert("x")</script>')
        self.assertEqual(self.write({"sales_discord_link": "https://phishing.example"})[0], 400)

if __name__ == "__main__":
    unittest.main()
