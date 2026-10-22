"""Settings from the environment. Secrets are read from files, never env values."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


def _read(path: str) -> str:
    return Path(path).read_text().strip() if path and Path(path).exists() else ""


def oauth_client(path: str) -> tuple[str, str]:
    """client_id and client_secret from the OAuth client JSON as downloaded from Google Cloud
    ({"web": {...}} or {"installed": {...}}). ("", "") if the file is missing or unreadable."""
    try:
        info = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return "", ""
    c = info.get("web") or info.get("installed") or info
    return c.get("client_id", ""), c.get("client_secret", "")


@dataclass
class Config:
    db_path: str
    base_path: str
    public_url: str
    headscale_url: str
    headscale_api_key: str
    oidc_issuer: str
    oidc_client_id: str
    oidc_client_secret: str
    session_secret: str
    bootstrap_admins: list[str]
    ssh_user: str
    ssh_socks: str
    interval: float
    dev_login: bool
    run_scheduler: bool
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    student_domains: tuple = ("g.bracu.ac.bd",)  # students' G Suite; personal and staff addresses are refused
    sheet_id: str = ""
    google_key_file: str = ""

    @classmethod
    def from_env(cls) -> "Config":
        e = os.environ.get
        data = e("LABSLOTS_DATA", "/data")
        return cls(
            db_path=e("LABSLOTS_DB", f"{data}/labslots.db"),
            base_path=e("LABSLOTS_BASE_PATH", "/slots").rstrip("/"),
            public_url=e("LABSLOTS_PUBLIC_URL", "https://hs.zamiulrashid.online").rstrip("/"),
            headscale_url=e("HEADSCALE_URL", "http://127.0.0.1:8080"),
            headscale_api_key=_read(e("HEADSCALE_API_KEY_FILE", "/run/secrets/headscale_api_key")),
            oidc_issuer=e("OIDC_ISSUER", "https://accounts.google.com"),
            # the downloaded OAuth client JSON wins; OIDC_CLIENT_ID + OIDC_CLIENT_SECRET_FILE still work
            oidc_client_id=oauth_client(e("GOOGLE_OAUTH_CLIENT_FILE", "/run/secrets/google-oauth-client.json"))[0]
            or e("OIDC_CLIENT_ID", ""),
            oidc_client_secret=oauth_client(e("GOOGLE_OAUTH_CLIENT_FILE", "/run/secrets/google-oauth-client.json"))[1]
            or _read(e("OIDC_CLIENT_SECRET_FILE", "/run/secrets/oidc_client_secret")),
            session_secret=_read(e("SESSION_SECRET_FILE", f"{data}/session_secret")),
            bootstrap_admins=[a.strip().lower() for a in e("LABSLOTS_BOOTSTRAP_ADMINS", "").split(",")
                              if a.strip()],
            ssh_user=e("LABSLOTS_SSH_USER", "labsched"),
            ssh_socks=e("LABSLOTS_SSH_SOCKS", ""),
            interval=float(e("LABSLOTS_INTERVAL", "30")),
            dev_login=e("LABSLOTS_DEV_LOGIN", "0") == "1",
            run_scheduler=e("LABSLOTS_RUN_SCHEDULER", "1") == "1",
            smtp_host=e("SMTP_HOST", ""),
            smtp_port=int(e("SMTP_PORT", "587")),
            smtp_user=e("SMTP_USER", ""),
            smtp_password=_read(e("SMTP_PASSWORD_FILE", "/run/secrets/smtp_password")),
            smtp_from=e("SMTP_FROM", ""),
            student_domains=tuple(d.strip().lower() for d in e("LABSLOTS_STUDENT_DOMAINS",
                                                                "g.bracu.ac.bd").split(",") if d.strip()),
            sheet_id=e("LABSLOTS_SHEET", ""),
            google_key_file=e("GOOGLE_SA_KEY_FILE", "/run/secrets/google-service-account.json"),
        )
