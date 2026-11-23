"""Unit tests for asc_signing.py: no network, `call` is replaced by a fake that answers from a dict."""
import os
import pathlib
import plistlib
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
        answer = self.answers.get((method, path), self.answers.get(path, {}))
        if isinstance(answer, Exception):
            raise answer
        return answer

    def env_lines(self):
        env = pathlib.Path(os.environ["GITHUB_ENV"])
        return env.read_text(encoding="utf-8").splitlines() if env.exists() else []

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
        for name in ("ASC_PROFILE_ID", "ASC_WIDGET_PROFILE_ID", "ASC_CERT_ID"):
            self.addCleanup(os.environ.pop, name, None)
        os.environ.update(ASC_PROFILE_ID="p1", ASC_WIDGET_PROFILE_ID="p2", ASC_CERT_ID="c1")
        asc_signing.cleanup()
        self.assertEqual(self.calls, [("DELETE", "profiles/p1"), ("DELETE", "profiles/p2"), ("DELETE", "certificates/c1")])

    def test_check_options_export_locally_and_keep_the_rest(self):
        upload = asc_signing.export_options("tw.x.app", "TEAM1", "P-app", "P-widget")
        check = asc_signing.check_options(upload)
        self.assertEqual(check["destination"], "export")
        self.assertEqual(upload["destination"], "upload")
        self.assertEqual({k: v for k, v in check.items() if k != "destination"}, {k: v for k, v in upload.items() if k != "destination"})

    def test_group_entitlements_match_project_yml(self):
        # project.yml: com.apple.security.application-groups: ['$(APP_GROUP_ID)'], APP_GROUP_ID = group.$(ETF_APP_BUNDLE_ID).
        self.assertEqual(asc_signing.group_entitlements("tw.x.app"), {"com.apple.security.application-groups": ["group.tw.x.app"]})

    def test_written_check_options_and_entitlements(self):
        asc_signing.folder.mkdir(parents=True, exist_ok=True)
        (asc_signing.folder / "ExportOptions.plist").write_bytes(plistlib.dumps(
            dict(method="app-store-connect", destination="upload", teamID="TEAM1", signingStyle="automatic")))
        self.addCleanup(os.environ.pop, "ETF_BUNDLE_ID", None)
        os.environ["ETF_BUNDLE_ID"] = "tw.x.app"
        asc_signing.write_check_options()
        asc_signing.write_entitlements()
        check = plistlib.loads((asc_signing.folder / "ExportOptions-check.plist").read_bytes())
        self.assertEqual((check["destination"], check["signingStyle"], check["teamID"]), ("export", "automatic", "TEAM1"))
        groups = plistlib.loads((asc_signing.folder / "app-group.entitlements").read_bytes())
        self.assertEqual(groups, {"com.apple.security.application-groups": ["group.tw.x.app"]})

    def test_prepare_falls_back_to_cloud_signing_after_both_checks(self):
        asc_signing.folder.mkdir(parents=True, exist_ok=True)
        pathlib.Path(os.environ["GITHUB_ENV"]).write_text("", encoding="utf-8")
        self.addCleanup(os.environ.pop, "ETF_BUNDLE_ID", None)
        os.environ["ETF_BUNDLE_ID"] = "tw.x.app"
        lookup = "bundleIds?limit=200&filter[identifier]="
        self.answers[lookup + "tw.x.app"] = {"data": [{"id": "B1", "attributes": {"identifier": "tw.x.app", "seedId": "TEAM1"}}]}
        self.answers[lookup + "tw.x.app.widget"] = {"data": [{"id": "B2", "attributes": {"identifier": "tw.x.app.widget", "seedId": "TEAM1"}}]}
        groups = {"data": [{"attributes": {"capabilityType": "APP_GROUPS"}}]}
        self.answers["bundleIds/B1/bundleIdCapabilities"] = groups
        self.answers["bundleIds/B2/bundleIdCapabilities"] = groups
        self.answers["certificates?limit=200"] = {"data": []}
        self.answers[("POST", "certificates")] = asc_signing.ApiError("App Store Connect POST certificates: HTTP 409.")
        asc_signing.prepare()
        # Both ids and both App Groups are checked before the certificate is asked for; nothing else is created.
        self.assertEqual(self.calls, [("GET", lookup + "tw.x.app"), ("GET", lookup + "tw.x.app.widget"),
                                      ("GET", "bundleIds/B1/bundleIdCapabilities"), ("GET", "bundleIds/B2/bundleIdCapabilities"),
                                      ("GET", "certificates?limit=200"), ("POST", "certificates")])
        self.assertEqual(self.env_lines(), ["APPLE_TEAM_ID=TEAM1", "SIGNING=cloud"])
        options = plistlib.loads((asc_signing.folder / "ExportOptions.plist").read_bytes())
        self.assertEqual((options["signingStyle"], options["destination"], options["teamID"]), ("automatic", "upload", "TEAM1"))

    def test_prepare_stops_before_anything_is_created_without_the_widget_id(self):
        self.addCleanup(os.environ.pop, "ETF_BUNDLE_ID", None)
        os.environ["ETF_BUNDLE_ID"] = "tw.x.app"
        lookup = "bundleIds?limit=200&filter[identifier]="
        self.answers[lookup + "tw.x.app"] = {"data": [{"id": "B1", "attributes": {"identifier": "tw.x.app", "seedId": "TEAM1"}}]}
        self.answers[lookup + "tw.x.app.widget"] = {"data": []}
        with self.assertRaises(asc_signing.ApiError):
            asc_signing.prepare()
        self.assertFalse(any(method == "POST" for method, _ in self.calls))


if __name__ == "__main__":
    unittest.main()
