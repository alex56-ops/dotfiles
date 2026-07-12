#!/usr/bin/env python3
"""Verwaltet DNS-Records der hb-studios.de-Zone per INWX-DomRobot-API.

Zugangsdaten kommen aus dem Cluster-Secret inwx-credentials-hbstudios
(Namespace cert-manager) — dasselbe, das der cert-manager-Webhook für
DNS-01-Challenges nutzt. Die 2FA wird per TOTP aus dem otpKey bedient.
Nur Python-Standardbibliothek. Aufruf über die Shell-Funktion hb-inwx-dns.
"""

import argparse
import base64
import hashlib
import hmac
import http.cookiejar
import json
import struct
import subprocess
import sys
import time
import urllib.request

API = "https://api.domrobot.com/jsonrpc/"
DOMAIN = "hb-studios.de"
SECRET = ("inwx-credentials-hbstudios", "cert-manager")


def kubectl_secret(name: str, ns: str) -> dict:
    out = subprocess.run(
        ["kubectl", "get", "secret", name, "-n", ns, "-o", "jsonpath={.data}"],
        capture_output=True, text=True, check=True,
    ).stdout
    return {k: base64.b64decode(v).decode() for k, v in json.loads(out).items()}


def totp(secret_b32: str) -> str:
    key = base64.b32decode(
        secret_b32.upper().replace(" ", "") + "=" * (-len(secret_b32) % 8)
    )
    counter = struct.pack(">Q", int(time.time()) // 30)
    digest = hmac.new(key, counter, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{code:06d}"


opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
)


def call(method: str, params: dict) -> dict:
    payload = json.dumps({"method": method, "params": params}).encode()
    req = urllib.request.Request(
        API, data=payload, headers={"Content-Type": "application/json"}
    )
    with opener.open(req, timeout=30) as resp:
        result = json.load(resp)
    # 1000 = ok, 1500 = ok + Session beendet (logout), 2302 = Object exists
    if result.get("code") not in (1000, 1500, 2302):
        raise SystemExit(
            f"INWX-Fehler bei {method}: code={result.get('code')} msg={result.get('msg')}"
        )
    return result


def login() -> None:
    creds = kubectl_secret(*SECRET)
    result = call("account.login", {"user": creds["username"], "pass": creds["password"]})
    if result.get("resData", {}).get("tfa", "0") not in ("0", ""):
        call("account.unlock", {"tan": totp(creds["otpKey"])})


def zone_records() -> list[dict]:
    info = call("nameserver.info", {"domain": DOMAIN})
    return info.get("resData", {}).get("record", [])


def fqdn(name: str) -> str:
    return name if name.endswith(DOMAIN) else f"{name}.{DOMAIN}"


def cmd_list(_: argparse.Namespace) -> None:
    for r in sorted(zone_records(), key=lambda r: (r["type"], r["name"])):
        print(f"{r['name']:<45} {r['type']:<6} {r['content']}  (ttl {r['ttl']}, id {r['id']})")


def cmd_add(args: argparse.Namespace) -> None:
    name = fqdn(args.name)
    existing = {(r["name"], r["type"]): r for r in zone_records()}
    if (name, args.type) in existing:
        r = existing[(name, args.type)]
        print(f"existiert bereits: {name} {args.type} → {r['content']} (nichts geändert)")
        return
    call("nameserver.createRecord", {
        "domain": DOMAIN, "type": args.type,
        "name": name.removesuffix(f".{DOMAIN}"),
        "content": args.content, "ttl": args.ttl,
    })
    print(f"angelegt: {name} {args.type} → {args.content} (ttl {args.ttl})")


def cmd_del(args: argparse.Namespace) -> None:
    name = fqdn(args.name)
    matches = [r for r in zone_records() if r["name"] == name and r["type"] == args.type]
    if not matches:
        raise SystemExit(f"kein Record {name} ({args.type}) gefunden")
    for r in matches:
        call("nameserver.deleteRecord", {"id": r["id"]})
        print(f"gelöscht: {r['name']} {r['type']} → {r['content']}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="hb-inwx-dns")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="alle Records der Zone anzeigen")

    p_add = sub.add_parser("add", help="Record anlegen (idempotent)")
    p_add.add_argument("name", help="Record-Name (mit oder ohne .hb-studios.de)")
    p_add.add_argument("content", help="Ziel/Inhalt des Records")
    p_add.add_argument("type", nargs="?", default="CNAME", help="Record-Typ (Default: CNAME)")
    p_add.add_argument("ttl", nargs="?", type=int, default=3600, help="TTL (Default: 3600)")

    p_del = sub.add_parser("del", help="Record löschen")
    p_del.add_argument("name", help="Record-Name (mit oder ohne .hb-studios.de)")
    p_del.add_argument("type", nargs="?", default="CNAME", help="Record-Typ (Default: CNAME)")

    args = parser.parse_args()
    args.type = getattr(args, "type", "CNAME")
    if hasattr(args, "type"):
        args.type = args.type.upper()

    login()
    try:
        {"list": cmd_list, "add": cmd_add, "del": cmd_del}[args.cmd](args)
    finally:
        call("account.logout", {})


if __name__ == "__main__":
    main()
