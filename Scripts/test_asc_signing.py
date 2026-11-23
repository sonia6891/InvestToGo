"""Unit tests for asc_signing.py: no network, `call` is replaced by a fake that answers from a dict."""
import os
import pathlib
import sys
import tempfile
import unittest

_temp = tempfile.mkdtemp()
os.environ["RUNNER_TEMP"] = _temp
os.environ["GITHUB_ENV"] = str(pathlib.Path(_temp) / "github_env")
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import asc_signing  # noqa: E402


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.answers = {}
        asc_signing.call = self.fake_call

    def fake_call(self, method, path, body=None):
        self.calls.append((method, path))
        return self.answers.get(path, {})

    def test_export_options_name_both_profiles(self):
        o = asc_signing.export_options("tw.x.app", "TEAM1", "P-app", "P-widget")
        self.assertEqual(o["provisioningProfiles"], {"tw.x.app": "P-app", "tw.x.app.widget": "P-widget"})
        self.assertEqual((o["signingStyle"], o["teamID"], o["method"]), ("manual", "TEAM1", "app-store-connect"))

    def test_missing_widget_bundle_names_it(self):
        self.answers["bundleIds?limit=200&filter[identifier]=tw.x.app.widget"] = {"data": []}
        with self.assertRaises(asc_signing.ApiError) as e:
            asc_signing.find_bundle("tw.x.app.widget")
        self.assertIn("tw.x.app.widget", str(e.exception))
        self.assertIn("開發者網站", str(e.exception))

    def test_without_app_groups_fails(self):
        self.answers["bundleIds/B1/bundleIdCapabilities"] = {"data": [{"attributes": {"capabilityType": "PUSH_NOTIFICATIONS"}}]}
        with self.assertRaises(asc_signing.ApiError) as e:
            asc_signing.require_app_groups("B1", "tw.x.app")
        self.assertIn("App Groups", str(e.exception))
        self.assertIn("group.tw.x.app", str(e.exception))

    def test_with_app_groups_passes(self):
        self.answers["bundleIds/B1/bundleIdCapabilities"] = {"data": [{"attributes": {"capabilityType": "APP_GROUPS"}}]}
        asc_signing.require_app_groups("B1", "tw.x.app")

    def test_cleanup_deletes_both_profiles_then_the_certificate(self):
        os.environ.update(ASC_PROFILE_ID="p1", ASC_WIDGET_PROFILE_ID="p2", ASC_CERT_ID="c1")
        asc_signing.cleanup()
        self.assertEqual(self.calls, [("DELETE", "profiles/p1"), ("DELETE", "profiles/p2"), ("DELETE", "certificates/c1")])


if __name__ == "__main__":
    unittest.main()
