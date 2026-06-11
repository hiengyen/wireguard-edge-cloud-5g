#!/usr/bin/env python3
"""
gen-agent-token.py — Tạo JWT dài hạn (10 năm) cho peersight-agent / broker
Dùng stdlib Python3, không cần cài thêm thư viện.

Cách chạy:
  python3 peersight/scripts/gen-agent-token.py
"""
import hmac
import hashlib
import base64
import json
import time
import os
import sys


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_jwt(secret: str, user_id: str, role: str, years: int = 10) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    now = int(time.time())
    exp = now + years * 365 * 24 * 3600
    payload = b64url(json.dumps({
        "user_id": user_id,
        "role":    role,
        "exp":     exp,
        "iat":     now,
        "iss":     "peersight-api",
    }).encode())
    msg = f"{header}.{payload}".encode()
    sig = b64url(hmac.new(secret.encode(), msg, hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"


# ── Tìm PEERSIGHT_JWT_SECRET ────────────────────────────────────
secret = os.environ.get("PEERSIGHT_JWT_SECRET", "")

if not secret:
    # Thử đọc từ .env hoặc .env.cloud trong thư mục gốc repo
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.join(script_dir, "..", "..")

    for filename in [".env", ".env.cloud"]:
        env_file = os.path.normpath(os.path.join(repo_root, filename))
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("PEERSIGHT_JWT_SECRET=") and not line.startswith("#"):
                        secret = line.split("=", 1)[1].strip().strip("'\"")
                        break
            if secret:
                break

if not secret:
    print("[ERROR] Không tìm thấy PEERSIGHT_JWT_SECRET.")
    print("        Đặt biến môi trường trước khi chạy:")
    print("          export PEERSIGHT_JWT_SECRET=your-secret")
    sys.exit(1)

# UUID cố định đại diện cho "system agent user" (không cần tồn tại trong DB)
AGENT_USER_ID = "00000000-0000-0000-0000-000000000002"

token = make_jwt(secret, AGENT_USER_ID, "admin", years=10)

print()
print("=" * 64)
print("  PEERSIGHT AGENT TOKEN  (valid 10 years)")
print("=" * 64)
print(token)
print("=" * 64)
print()
print("Dùng token này cho:")
print("  PEERSIGHT_TOKEN  — trong install-agent.sh")
print("  PEERSIGHT_BROKER_TOKEN  — trong file .env (broker)")
print()
print("Lệnh cài agent:")
print("  cd ~/wireguard-edge-cloud-5g")
print(f"  sudo -E PEERSIGHT_API_URL=\"http://10.8.0.1:4000\" \\")
print(f"       PEERSIGHT_HOST_ID=\"<uuid-from-hosts-page>\" \\")
print(f"       PEERSIGHT_TOKEN=\"{token[:40]}...\" \\")
print(f"       bash peersight/install-agent.sh")
print()
