"""Temporary App Store signing from an App Store Connect API key alone, for the TestFlight workflow.

prepare: finds the app's Bundle ID (and with it the team), creates an Apple Distribution certificate for a new key and an
App Store provisioning profile for it, and leaves them for the keychain and the export: certificate.p12 and
ExportOptions.plist in $RUNNER_TEMP/etf-signing, the profile in the provisioning folders, names and IDs in $GITHUB_ENV.
cleanup: deletes that profile and revokes that certificate, so each run starts clean and the account's certificate limit
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


def prepare() -> None:
    bundle = os.environ["ETF_BUNDLE_ID"]
    listed = call("GET", "bundleIds?limit=200&filter[identifier]=" + urllib.parse.quote(bundle))["data"]
    found = [item for item in listed if item["attributes"]["identifier"] == bundle]
    if not found:
        raise ApiError(f"App Store Connect 找不到 Bundle ID {bundle}；請確認變數 ETF_BUNDLE_ID 與 App Store Connect 的 App 相同。")
    bundle_id, team = found[0]["id"], found[0]["attributes"]["seedId"]

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

    name = f"ETFToGo TestFlight {os.environ.get('GITHUB_RUN_ID', int(time.time()))}"
    profile = call("POST", "profiles", {"data": {"type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                          "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
    write_env(ASC_PROFILE_ID=profile["id"])
    uuid = profile["attributes"]["uuid"]
    content = base64.b64decode(profile["attributes"]["profileContent"])
    for directory in ("Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"):
        target = pathlib.Path.home() / directory
        target.mkdir(parents=True, exist_ok=True)
        (target / f"{uuid}.mobileprovision").write_bytes(content)

    export = dict(method="app-store-connect", destination="upload", teamID=team, signingStyle="manual",
                  signingCertificate="Apple Distribution", provisioningProfiles={bundle: name},
                  manageAppVersionAndBuildNumber=False, uploadSymbols=True, stripSwiftSymbols=True)
    (folder / "ExportOptions.plist").write_bytes(plistlib.dumps(export))
    write_env(APPLE_TEAM_ID=team, PROFILE_UUID=uuid, PROFILE_NAME=name, P12_PASSWORD=password)
    print(f"Prepared signing for {bundle} (team {team}) with a temporary certificate and profile.")


def cloud(bundle: str, team: str) -> None:
    """Cloud signing: the archive is built unsigned and the export signs it with the team's cloud-managed distribution
    certificate through the API key (Admin role), so no certificate is created."""
    export = dict(method="app-store-connect", destination="upload", teamID=team, signingStyle="automatic",
                  manageAppVersionAndBuildNumber=False, uploadSymbols=True, stripSwiftSymbols=True)
    (folder / "ExportOptions.plist").write_bytes(plistlib.dumps(export))
    write_env(APPLE_TEAM_ID=team, SIGNING="cloud")
    print(f"Prepared cloud signing for {bundle} (team {team}).")


def cleanup() -> None:
    for kind, name in (("profiles", "ASC_PROFILE_ID"), ("certificates", "ASC_CERT_ID")):
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
