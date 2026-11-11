"""App Store Connect chores with the same API key as the TestFlight upload (see asc_signing.py for the token).

rename <name>: sets the app's name on every editable App Information localization.
testflight [build]: waits for that build (default: the newest) to appear and finish processing, then makes sure every
internal TestFlight group has it. A just-uploaded build takes a few minutes to show up at all, so name it.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ETF_BUNDLE_ID, RUNNER_TEMP (the key in $RUNNER_TEMP/etf-signing/AuthKey.p8).
"""
import os
import sys
import time
import urllib.parse

from asc_signing import ApiError, call


def app_id() -> str:
    bundle = os.environ["ETF_BUNDLE_ID"]
    apps = [a for a in call("GET", "apps?filter[bundleId]=" + urllib.parse.quote(bundle))["data"] if a["attributes"]["bundleId"] == bundle]
    if not apps:
        raise ApiError(f"App Store Connect 沒有 Bundle ID 為 {bundle} 的 App。")
    print(f"App: {apps[0]['attributes']['name']} ({apps[0]['id']})")
    return apps[0]["id"]


def rename(name: str) -> None:
    app = app_id()
    changed = 0
    for info in call("GET", f"apps/{app}/appInfos")["data"]:
        state = info["attributes"].get("state") or info["attributes"].get("appStoreState")
        for loc in call("GET", f"appInfos/{info['id']}/appInfoLocalizations")["data"]:
            old = loc["attributes"].get("name")
            if old == name:
                print(f"{loc['attributes']['locale']} ({state}): already {name}")
                continue
            try:
                call("PATCH", f"appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {"name": name}}})
                print(f"{loc['attributes']['locale']} ({state}): {old} -> {name}")
                changed += 1
            except ApiError as error:
                print(f"::warning::{loc['attributes']['locale']} ({state}) not changed: {error}")
    print(f"Renamed {changed} localization(s).")


def testflight(version: str = "") -> None:
    app = app_id()
    deadline = time.time() + 45 * 60
    while True:
        query = f"builds?filter[app]={app}&sort=-uploadedDate&limit=1" + (f"&filter[version]={urllib.parse.quote(version)}" if version else "")
        builds = call("GET", query)["data"]
        if not builds:
            if version and time.time() < deadline:
                print(f"Build {version}: not listed yet")
                time.sleep(60)
                continue
            raise ApiError(f"找不到組建 {version or ''}。".replace(" 。", "。"))
        build = builds[0]
        state = build["attributes"]["processingState"]
        print(f"Build {build['attributes']['version']}: {state}")
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            raise ApiError(f"組建 {build['attributes']['version']} 處理失敗（{state}），請查看 App Store Connect 的電子郵件。")
        if time.time() > deadline:
            raise ApiError("等了 45 分鐘組建仍在處理中，請稍後在 TestFlight 查看。")
        time.sleep(60)
    for group in call("GET", f"betaGroups?filter[app]={app}&limit=50")["data"]:
        attrs = group["attributes"]
        if not attrs.get("isInternalGroup"):
            continue
        if attrs.get("hasAccessToAllBuilds"):
            print(f"Internal group {attrs['name']}: gets every build automatically.")
            continue
        call("POST", f"betaGroups/{group['id']}/relationships/builds", {"data": [{"type": "builds", "id": build["id"]}]})
        print(f"Internal group {attrs['name']}: build {build['attributes']['version']} added.")
    print(f"Build {build['attributes']['version']} is ready in TestFlight.")


def certificates() -> None:
    """The team's distribution certificates and where each came from, read only: the request a certificate was made
    from names its maker (this workflow's temporary ones say ETFToGo TestFlight); one without a request was made by
    Apple (cloud-managed) or by Xcode."""
    import base64
    from cryptography import x509
    for c in call("GET", "certificates?limit=200")["data"]:
        a = c["attributes"]
        if a.get("certificateType") not in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
            continue
        maker = "no request on file"
        csr = a.get("csrContent")
        if csr:
            try:
                text = csr if "BEGIN" in csr else f"-----BEGIN CERTIFICATE REQUEST-----\n{csr}\n-----END CERTIFICATE REQUEST-----\n"
                maker = "request from " + x509.load_pem_x509_csr(text.encode()).subject.rfc4514_string()
            except Exception as error:
                maker = f"request unreadable ({type(error).__name__})"
        issued = ""
        if a.get("certificateContent"):
            cert = x509.load_der_x509_certificate(base64.b64decode(a["certificateContent"]))
            issued = f"issued {cert.not_valid_before_utc:%Y-%m-%d %H:%M} UTC · subject {cert.subject.rfc4514_string()}"
        print(f"{a.get('certificateType')} · name {a.get('name')} · {issued} · expires {a.get('expirationDate', '')[:10]} · {maker}")


if __name__ == "__main__":
    try:
        if sys.argv[1] == "rename":
            rename(sys.argv[2])
        elif sys.argv[1] == "certificates":
            certificates()
        elif sys.argv[1] == "testflight":
            testflight(sys.argv[2] if len(sys.argv) > 2 else "")
        else:
            raise SystemExit("usage: asc_app.py rename <name> | testflight")
    except ApiError as error:
        print(f"::error::{error}")
        sys.exit(1)
