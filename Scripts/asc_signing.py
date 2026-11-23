"""Temporary App Store signing from an App Store Connect API key alone, for the TestFlight workflow.

prepare: finds the app's Bundle ID (and with it the team) and the home-screen widget's (<id>.widget), checks that both have
App Groups on, creates an Apple Distribution certificate for a new key and an App Store provisioning profile for each
bundle, and leaves them for the keychain and the export: certificate.p12 and ExportOptions.plist in
$RUNNER_TEMP/etf-signing, the profiles in the provisioning folders, names and IDs in $GITHUB_ENV.
cleanup: deletes those profiles and revokes that certificate, so each run starts clean and the account's certificate limit
is never reached. Builds already uploaded are not affected: Apple re-signs them for TestFlight and the App Store.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ETF_BUNDLE_ID, RUNNER_TEMP, GITHUB_ENV; the key in $RUNNER_TEMP/etf-signing/AuthKey.p8.
Nothing secret is printed. Needs the `cryptography` package.
"""
import base64
import json
import os
import pathlib
import plistlib
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1/"
folder = pathlib.Path(os.environ["RUNNER_TEMP"]) / "etf-signing"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token() -> str:
    """A 15-minute ES256 token for the App Store Connect API."""
    key = serialization.load_pem_private_key((folder / "AuthKey.p8").read_bytes(), password=None)
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = b64url(json.dumps(header).encode()) + "." + b64url(json.dumps(claims).encode())
    r, s = decode_dss_signature(key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
    return signing_input + "." + b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


class ApiError(Exception):
    pass


def call(method: str, path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                     headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        try:
            detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in json.loads(detail).get("errors", []))
        except ValueError:
            pass
        hint = {401: "API 金鑰無效：Key ID、Issuer ID 或 .p8 內容不相符。",
                403: "API 金鑰權限不足：請改用「管理」(Admin) 權限的金鑰。"}.get(error.code, "")
        raise ApiError(f"App Store Connect {method} {path.split('?')[0]}: HTTP {error.code}. {hint} {detail}") from None


def write_env(**values: str) -> None:
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
        for name, value in values.items():
            env.write(f"{name}={value}\n")


def find_bundle(identifier: str) -> tuple[str, str]:
    """(resource id, team seedId) of a Bundle ID; ApiError when the account has none."""
    listed = call("GET", "bundleIds?limit=200&filter[identifier]=" + urllib.parse.quote(identifier))["data"]
    found = [item for item in listed if item["attributes"]["identifier"] == identifier]
    if not found:
        if identifier.endswith(".widget"):
            main = identifier[:-len(".widget")]
            raise ApiError(f"App Store Connect 找不到小工具的 Bundle ID {identifier}；請先在開發者網站註冊它並開啟 App Groups（group.{main}）。")
        raise ApiError(f"App Store Connect 找不到 Bundle ID {identifier}；請確認變數 ETF_BUNDLE_ID 與 App Store Connect 的 App 相同。")
    return found[0]["id"], found[0]["attributes"]["seedId"]


def require_app_groups(resource_id: str, identifier: str) -> None:
    """ApiError unless the Bundle ID has the App Groups capability (the widget shares the app's data through one)."""
    capabilities = call("GET", f"bundleIds/{resource_id}/bundleIdCapabilities")["data"]
    if not any(c["attributes"].get("capabilityType") == "APP_GROUPS" for c in capabilities):
        main = identifier[:-len(".widget")] if identifier.endswith(".widget") else identifier
        raise ApiError(f"Bundle ID {identifier} 沒有開啟 App Groups；請在開發者網站開啟並指定 group.{main}。")


def make_profile(bundle_resource_id: str, cert_id: str, name: str) -> tuple[str, str]:
    """An App Store profile for one Bundle ID and the certificate, installed in both provisioning folders; (uuid, name)."""
    profile = call("POST", "profiles", {"data": {"type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                          "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})["data"]
    write_env(**{"ASC_WIDGET_PROFILE_ID" if "Widget" in name else "ASC_PROFILE_ID": profile["id"]})  # recorded as soon as it exists, so cleanup deletes it even if a later step fails
    uuid = profile["attributes"]["uuid"]
    content = base64.b64decode(profile["attributes"]["profileContent"])
    for directory in ("Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"):
        target = pathlib.Path.home() / directory
        target.mkdir(parents=True, exist_ok=True)
        (target / f"{uuid}.mobileprovision").write_bytes(content)
    return uuid, name


def export_options(bundle: str, team: str, app_profile: str, widget_profile: str) -> dict:
    return dict(method="app-store-connect", destination="upload", teamID=team, signingStyle="manual",
                signingCertificate="Apple Distribution",
                provisioningProfiles={bundle: app_profile, bundle + ".widget": widget_profile},
                manageAppVersionAndBuildNumber=False, uploadSymbols=True, stripSwiftSymbols=True)


def prepare() -> None:
    bundle = os.environ["ETF_BUNDLE_ID"]
    widget = bundle + ".widget"
    # Both ids and their App Groups are checked before anything is created, so a missing portal step costs nothing.
    bundle_id, team = find_bundle(bundle)
    widget_id, _ = find_bundle(widget)
    require_app_groups(bundle_id, bundle)
    require_app_groups(widget_id, widget)

    # What the account already holds: the distribution certificate limit is per team.
    existing = [c for c in call("GET", "certificates?limit=200")["data"]
                if c["attributes"].get("certificateType") in ("DISTRIBUTION", "IOS_DISTRIBUTION")]
    print(f"Distribution certificates on the account: {len(existing)}")
    for c in existing:
        a = c["attributes"]
        print(f"  {a.get('certificateType')} · {a.get('displayName') or a.get('name')} · expires {a.get('expirationDate', '')[:10]} · platform {a.get('platform')}")

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "ETFToGo TestFlight")]))
           .sign(key, hashes.SHA256()))
    try:
        cert = call("POST", "certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr.public_bytes(serialization.Encoding.PEM).decode()}}})["data"]
    except ApiError as error:
        if "409" not in str(error):
            raise
        # The team already holds as many distribution certificates as Apple allows (another app's among them):
        # leave them alone and let Xcode sign with Apple's cloud-managed certificate instead.
        print("::notice::The account's distribution certificate limit is reached; signing in the cloud instead.")
        cloud(bundle, team)
        return
    write_env(ASC_CERT_ID=cert["id"])  # recorded first, so cleanup revokes it even if a later step fails
    certificate = x509.load_der_x509_certificate(base64.b64decode(cert["attributes"]["certificateContent"]))
    password = secrets.token_hex(16)
    print("::add-mask::" + password)
    # 3DES/SHA-1 PKCS#12: the format the macOS keychain imports.
    encryption = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(2048)
                  .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1())
                  .build(password.encode()))
    (folder / "certificate.p12").write_bytes(pkcs12.serialize_key_and_certificates(b"ETFToGo TestFlight", key, certificate, None, encryption))

    run = os.environ.get("GITHUB_RUN_ID", int(time.time()))
    name, widget_name = f"ETFToGo TestFlight {run}", f"ETFToGo Widget TestFlight {run}"
    uuid, _ = make_profile(bundle_id, cert["id"], name)
    widget_uuid, _ = make_profile(widget_id, cert["id"], widget_name)
    (folder / "ExportOptions.plist").write_bytes(plistlib.dumps(export_options(bundle, team, name, widget_name)))
    write_env(APPLE_TEAM_ID=team, PROFILE_UUID=uuid, PROFILE_NAME=name, WIDGET_PROFILE_UUID=widget_uuid,
              WIDGET_PROFILE_NAME=widget_name, P12_PASSWORD=password)
    print(f"Prepared signing for {bundle} (team {team}) with a temporary certificate and profiles.")


def cloud(bundle: str, team: str) -> None:
    """Cloud signing: the archive is built unsigned and the export signs it with the team's cloud-managed distribution
    certificate through the API key (Admin role), so no certificate is created."""
    export = dict(method="app-store-connect", destination="upload", teamID=team, signingStyle="automatic",
                  manageAppVersionAndBuildNumber=False, uploadSymbols=True, stripSwiftSymbols=True)
    (folder / "ExportOptions.plist").write_bytes(plistlib.dumps(export))
    write_env(APPLE_TEAM_ID=team, SIGNING="cloud")
    print(f"Prepared cloud signing for {bundle} (team {team}).")


def cleanup() -> None:
    for kind, name in (("profiles", "ASC_PROFILE_ID"), ("profiles", "ASC_WIDGET_PROFILE_ID"), ("certificates", "ASC_CERT_ID")):
        if os.environ.get(name):
            try:
                call("DELETE", f"{kind}/{os.environ[name]}")
                print(f"Removed the temporary {kind[:-1]}.")
            except ApiError as error:
                print(f"::warning::{error}")


if __name__ == "__main__":
    try:
        {"prepare": prepare, "cleanup": cleanup}[sys.argv[1]]()
    except ApiError as error:
        print(f"::error::{error}")
        sys.exit(1)
