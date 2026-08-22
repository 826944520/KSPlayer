#!/usr/bin/env python3
"""Free Apple ID automatic provisioning for KSPlayer demo sideloading.

Replaces the manual 爱思助手 sign step: logs into the user's Apple ID (web
auth flow with anisette from 爱思助手's Anisette.exe), registers the device
UDID, creates a development certificate + provisioning profile, and writes
certs/ so Tools/Deploy/deploy.ps1 can sign with zsign.

IMPORTANT: use a secondary Apple ID (free accounts are limited; the profile
expires in 7 days — re-run `all` to renew).

Usage:
  python provision.py all --apple-id you@example.com --udid <UDID> --bundle com.kingsplayer.DemoApp
  python provision.py login   --apple-id you@example.com          # auth + cache cookies
  python provision.py device  --udid <UDID>                       # register device
  python provision.py cert                                        # create cert
  python provision.py profile --bundle com.kingsplayer.DemoApp    # create app id + profile

Password is prompted interactively (never stored). 2FA is approved on the
trusted iPhone (push) — tap Allow when prompted.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time

import requests

BASE_URL = "https://developerservices2.apple.com/services/QH65B2"
SIGNIN_URL = "https://appleid.apple.com/signin"
AUTH_BASE = "https://idmsa.apple.com/appleauth/auth"
WIDGET_KEY = "d39ba9916b7251055b270c75f77291f9"  # appleid.apple.com web widget key
ANISETTE = r"C:\Program Files\i4Tools9\iCloudDll\Anisette.exe"
CERT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "certs")
SESSION_FILE = os.path.join(CERT_DIR, "session.json")
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "provision.log")

CERT_TYPE_IOS_DEV = "5QPB9NHCEI"  # iOS Development

_LOG_H = None


def _open_log():
    global _LOG_H
    if _LOG_H is None:
        _LOG_H = open(LOG_FILE, "a", encoding="utf-8")
    return _LOG_H


def log(msg):
    line = f"[provision] {msg}"
    print(line, flush=True)
    try:
        _open_log().write(line + "\n")
        _open_log().flush()
    except Exception:
        pass


def log_raw(msg):
    print(msg, flush=True)
    try:
        _open_log().write(str(msg) + "\n")
        _open_log().flush()
    except Exception:
        pass


def anisette_headers():
    out = subprocess.run([ANISETTE], capture_output=True, text=True, timeout=15)
    if out.returncode != 0:
        raise RuntimeError(f"Anisette.exe failed: {out.stderr}")
    data = json.loads(out.stdout)
    return {k: str(v) for k, v in data.items()}


def get_password():
    import getpass
    return getpass.getpass("Apple ID password (not stored): ")


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

def login(apple_id, password=None):
    if password is None:
        password = get_password()
    s = requests.Session()
    ah = anisette_headers()
    log("fetching signin page for session cookies...")
    r = s.get(SIGNIN_URL, headers={**ah, "Accept": "text/html"}, timeout=30)
    log("posting credentials...")
    r = s.post(
        f"{AUTH_BASE}/signin",
        json={"accountName": apple_id, "password": password},
        headers={
            **ah,
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Apple-Widget-Key": WIDGET_KEY,
            "Referer": SIGNIN_URL + "/",
        },
        timeout=30,
    )
    if r.status_code == 200:
        log("logged in (no 2FA)")
    elif r.status_code == 409:
        session_id = r.headers.get("X-Apple-ID-Session-Id")
        scnt = r.headers.get("scnt")
        if not session_id or not scnt:
            raise RuntimeError(f"2FA challenge but no session headers: {dict(r.headers)} body={r.text[:300]}")
        log("2FA required — approve on your iPhone (tap Allow), or SMS if it fails...")
        auth_h = {
            **ah,
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Apple-ID-Session-Id": session_id,
            "scnt": scnt,
        }
        # 1) try trusted-device push (no code needed, user taps Allow on the phone)
        r2 = s.post(f"{AUTH_BASE}/verify/trusteddevice", json={}, headers=auth_h, timeout=120)
        if r2.status_code != 200:
            # 2) fall back to SMS code entry
            log("trusted-device push failed — SMS code flow...")
            code = input("SMS/6-digit verification code: ").strip()
            r2 = s.post(f"{AUTH_BASE}/verify/phone", json={"phoneNumber": {}, "securityCode": {"code": code}}, headers=auth_h, timeout=30)
            if r2.status_code != 200:
                raise RuntimeError(f"2FA failed: {r2.status_code} {r2.text[:300]}")
        log("authorizing...")
        r3 = s.get(f"{AUTH_BASE}/authorize", headers={**ah, "X-Apple-ID-Session-Id": session_id, "scnt": scnt, "Accept": "application/json"}, timeout=30)
        if r3.status_code != 200:
            raise RuntimeError(f"authorize failed: {r3.status_code} {r3.text[:300]}")
    else:
        raise RuntimeError(f"signin failed: {r.status_code} {r.text[:300]}")

    cookies = s.cookies.get_dict()
    myacinfo = cookies.get("myacinfo")
    if not myacinfo:
        raise RuntimeError(f"no myacinfo cookie. cookies={list(cookies.keys())}")
    os.makedirs(CERT_DIR, exist_ok=True)
    with open(SESSION_FILE, "w") as f:
        json.dump({"myacinfo": myacinfo, "all_cookies": cookies, "apple_id": apple_id}, f)
    log(f"session saved -> {SESSION_FILE}")
    return s


def get_session():
    if not os.path.exists(SESSION_FILE):
        raise RuntimeError("No session — run: provision.py login --apple-id <id>")
    with open(SESSION_FILE) as f:
        return json.load(f)


def api(session, method, path, payload=None):
    myacinfo = session["myacinfo"]
    h = {
        "Cookie": f"myacinfo={myacinfo}",
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "KSPlayer-Provision/1.0",
    }
    url = f"{BASE_URL}{path}"
    if method == "GET":
        r = requests.get(url, headers=h, timeout=30)
    else:
        r = requests.post(url, json=payload, headers=h, timeout=30)
    try:
        body = r.json()
    except Exception:
        raise RuntimeError(f"{path} -> HTTP {r.status_code}, non-JSON: {r.text[:300]}")
    code = body.get("resultCode")
    if code not in (0, "0", None):
        raise RuntimeError(f"{path} -> resultCode={code} userString={body.get('userString')} msg={body.get('resultString')} body={json.dumps(body)[:400]}")
    return body


# ---------------------------------------------------------------------------
# Provisioning steps
# ---------------------------------------------------------------------------

def step_device(udid):
    session = get_session()
    team = team_id(session)
    body = api(session, "POST", "/registerDevice", {"deviceNumber": udid, "teamId": team, "deviceName": "KSPlayer Demo"})
    log(f"device registered: {udid}")
    return body


def team_id(session):
    body = api(session, "GET", "/accountInfo")
    teams = body.get("teams") or body.get("accountInfo", {}).get("teams")
    if not teams:
        raise RuntimeError(f"no teams in accountInfo: {json.dumps(body)[:400]}")
    tid = teams[0].get("teamId")
    log(f"team: {tid} ({teams[0].get('name')})")
    return tid


def make_csr():
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID
    key = ec.generate_private_key(ec.SECP256R1())
    csr = x509.CertificateSigningRequestBuilder().subject_name(
        x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "KSPlayer Automatic")])
    ).sign(key, hashes.SHA256())
    with open(os.path.join(CERT_DIR, "key.pem"), "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    return csr.public_bytes(serialization.Encoding.PEM).decode()


def step_cert():
    session = get_session()
    team = team_id(session)
    csr = make_csr()
    body = api(session, "POST", "/addCertificate", {"csrContent": csr, "teamId": team, "certType": CERT_TYPE_IOS_DEV})
    cert = body.get("certRequest") or body
    cert_id = cert.get("certificateId") or cert.get("id")
    cert_content = cert.get("certificateContent") or cert.get("encodedCertificate")
    if not cert_content:
        raise RuntimeError(f"no certificateContent: {json.dumps(body)[:500]}")
    with open(os.path.join(CERT_DIR, "cert.pem"), "w") as f:
        f.write(cert_content)
    with open(os.path.join(CERT_DIR, "cert_id.json"), "w") as f:
        json.dump({"certId": cert_id, "certType": CERT_TYPE_IOS_DEV, "teamId": team}, f)
    log(f"certificate created (id={cert_id})")
    return cert_id


def step_profile(bundle_id):
    session = get_session()
    team = team_id(session)
    # App ID (explicit bundle id)
    app_body = api(session, "POST", "/addApplication", {"name": "KSPlayerDemo", "bundleId": bundle_id, "teamId": team, "type": "explicit"})
    app = app_body.get("appId") or app_body
    app_id = app.get("appIdId") or app.get("id")
    log(f"app id: {app_id}")
    # device + cert
    dev_body = api(session, "POST", "/registerDevice", {"deviceNumber": device_udid(), "teamId": team, "deviceName": "KSPlayer Demo"})
    dev = dev_body.get("device") or dev_body
    device_id = dev.get("deviceId") or dev.get("id")
    cert_id = json.load(open(os.path.join(CERT_DIR, "cert_id.json")))["certId"]
    # profile
    prof_body = api(session, "POST", "/addProvisioningProfile", {
        "appIdId": app_id,
        "certIds": [cert_id],
        "deviceIds": [device_id],
        "profileType": "limited",
        "templateName": "iOS App Development",
        "profileName": f"KSPlayerDemo-{time.strftime('%m%d')}",
        "teamId": team,
    })
    prof = prof_body.get("provisioningProfile") or prof_body
    encoded = prof.get("encodedProfile") or prof.get("provisioningProfileContent")
    if not encoded:
        raise RuntimeError(f"no encodedProfile: {json.dumps(prof_body)[:500]}")
    with open(os.path.join(CERT_DIR, "profile.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(encoded))
    log(f"provisioning profile saved ({len(base64.b64decode(encoded))} bytes)")
    return True


def device_udid():
    out = subprocess.run([sys.executable, "-m", "tidevice", "list"], capture_output=True, text=True)
    for line in out.stdout.splitlines():
        if line.strip() and line.strip()[0].isalnum() and "-" in line:
            return line.split()[0]
    raise RuntimeError("tidevice found no device (is the iPhone connected?)")


def main():
    p = argparse.ArgumentParser(description="Free Apple ID provisioning")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("login", help="login and cache session")
    a.add_argument("--apple-id", required=True)
    a.add_argument("--password", default=None)

    d = sub.add_parser("device", help="register device UDID")
    d.add_argument("--udid", default=None)

    sub.add_parser("cert", help="create development certificate")

    pr = sub.add_parser("profile", help="create provisioning profile")
    pr.add_argument("--bundle", required=True)

    allp = sub.add_parser("all", help="full pipeline: login + device + cert + profile")
    allp.add_argument("--apple-id", required=True)
    allp.add_argument("--password", default=None)
    allp.add_argument("--udid", default=None)
    allp.add_argument("--bundle", required=True)

    args = p.parse_args()

    if args.cmd == "login":
        login(args.apple_id, args.password)
    elif args.cmd == "device":
        step_device(args.udid or device_udid())
    elif args.cmd == "cert":
        step_cert()
    elif args.cmd == "profile":
        step_profile(args.bundle)
    elif args.cmd == "all":
        login(args.apple_id, args.password)
        step_device(args.udid or device_udid())
        step_cert()
        step_profile(args.bundle)
        log("DONE — certs ready in Tools/Deploy/certs/ (key.pem, cert.pem, profile.mobileprovision)")
        log("Now run: powershell -ExecutionPolicy Bypass -File Tools\\Deploy\\deploy.ps1")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        log_raw(f"ERROR: {e}")
        log_raw(traceback.format_exc())
        sys.exit(1)
