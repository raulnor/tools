#!/bin/bash
# claude-usage.5m.sh
# Claude.ai usage monitor for SwiftBar.
#
# REQUIRES: uv — https://astral.sh/uv
#
# INSTALL:
#   curl -o ~/Library/Application\ Support/SwiftBar/Plugins/claude-usage.sh \
#     https://tools.melvis.site/shell/claude-usage.sh
#   chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/claude-usage.5m.sh
#
# First run opens ~/.claude_usage_env for setup.

# Add common uv/pip install locations to PATH.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

exec uv run --script --quiet - << 'PYTHON'
# /// script
# requires-python = ">=3.10"
# dependencies = ["curl-cffi>=0.7"]
# ///

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from curl_cffi import requests as cf

ENV_FILE = Path.home() / ".claude_usage_env"

TEMPLATE = """\
# Claude usage monitor — https://tools.melvis.site/claude-usage-swiftbar.sh
#
# How to find your session key:
#   1. Open claude.ai in Chrome or Safari
#   2. Open DevTools → Application → Cookies → claude.ai
#   3. Copy the value of "sessionKey" (starts with sk-ant-sid02-)
#
# The key expires after a few weeks.
# When the menu bar shows ⚠️, paste a fresh one here and save.

CLAUDE_SESSION_KEY=
"""


def load_env() -> None:
    if not ENV_FILE.exists():
        ENV_FILE.write_text(TEMPLATE)
        ENV_FILE.chmod(0o600)
        subprocess.Popen(["open", str(ENV_FILE)])
        error_output("First run — fill in ~/.claude_usage_env (opening now...)")
        sys.exit(0)
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            if val.strip():
                os.environ[key.strip()] = val.strip()


_HEADERS = {
    "anthropic-client-platform": "web_claude_ai",
    "content-type": "application/json",
    "referer": "https://claude.ai/",
}


def _get(url: str, session_key: str) -> dict:
    r = cf.get(
        url,
        cookies={"sessionKey": session_key},
        headers=_HEADERS,
        impersonate="chrome",
        timeout=10,
    )
    if r.status_code == 401:
        raise RuntimeError("Session key expired — edit ~/.claude_usage_env")
    if r.status_code == 403:
        raise RuntimeError("Cloudflare blocked — session key may be expired")
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    return r.json()


def discover(session_key: str) -> str:
    orgs = _get("https://claude.ai/api/organizations", session_key)
    if not orgs:
        raise RuntimeError("No organizations found")
    org_id = orgs[0].get("uuid") or orgs[0].get("id")
    if not org_id:
        raise RuntimeError(f"Could not parse org ID: {orgs[0]}")
    return org_id


def fetch_usage(session_key: str, org_id: str) -> dict:
    return _get(f"https://claude.ai/api/organizations/{org_id}/usage", session_key)


def format_reset(resets_at: str) -> str:
    try:
        reset = datetime.fromisoformat(resets_at.replace("Z", "+00:00"))
        delta = reset - datetime.now(timezone.utc)
        if delta.total_seconds() <= 0:
            return "resetting..."
        hours, remainder = divmod(int(delta.total_seconds()), 3600)
        minutes = remainder // 60
        if hours >= 24:
            return f"{hours // 24}d"
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"
    except Exception:
        return "?"


def bar(percent: float, width: int = 10) -> str:
    filled = max(1, round(percent / 100 * width)) if percent > 0 else 0
    return "█" * min(filled, width) + "░" * (width - min(filled, width))


def color(percent: float) -> str:
    if percent >= 75:
        return "red"
    return "green"


def swiftbar_output(data: dict) -> None:
    five_hour = data.get("five_hour") or {}
    seven_day = data.get("seven_day") or {}
    spend = data.get("spend") or {}

    session_pct = float(five_hour.get("utilization") or 0)
    weekly_pct = float(seven_day.get("utilization") or 0)
    dominant = max(session_pct, weekly_pct)

    print(f"✦ {dominant:.0f}% | color={color(dominant)}")
    print("---")

    session_reset = format_reset(five_hour["resets_at"]) if five_hour.get("resets_at") else "?"
    print(f"Session:  {bar(session_pct)} {session_pct:.0f}% | color={color(session_pct)} font=Menlo size=12")
    print(f"Resets in {session_reset} | color=gray size=11")
    print("---")

    weekly_reset = format_reset(seven_day["resets_at"]) if seven_day.get("resets_at") else "?"
    print(f"Weekly:   {bar(weekly_pct)} {weekly_pct:.0f}% | color={color(weekly_pct)} font=Menlo size=12")
    print(f"Resets {weekly_reset} | color=gray size=11")

    if spend.get("enabled"):
        print("---")
        used = spend.get("used", {})
        amount = used.get("amount_minor", 0) / (10 ** used.get("exponent", 2))
        spend_pct = float(spend.get("percent") or 0)
        print(f"Credits:  {bar(spend_pct)} ${amount:.2f} ({spend_pct:.0f}%) | color={color(spend_pct)} font=Menlo size=12")

    limits = data.get("limits") or []
    extras = [l for l in limits if l.get("is_active") and l.get("kind") not in ("session", "weekly_all")]
    if extras:
        print("---")
        for limit in extras:
            pct = float(limit.get("percent") or 0)
            kind = limit.get("kind", "unknown").replace("_", " ")
            print(f"{kind}: {pct:.0f}% | color={color(pct)} size=11")

    print("---")
    print("Open Usage Settings | href=https://claude.ai/settings/usage")
    print(f"Edit credentials | bash=open param1={ENV_FILE} terminal=false")
    print("Refresh | refresh=true")


def error_output(msg: str) -> None:
    print("Claude ⚠️")
    print("---")
    print(msg)
    print("---")
    print("Open Usage Settings | href=https://claude.ai/settings/usage")
    print(f"Edit credentials | bash=open param1={ENV_FILE} terminal=false")
    print("Refresh | refresh=true")


def main() -> None:
    load_env()

    session_key = os.environ.get("CLAUDE_SESSION_KEY", "").strip()
    if not session_key:
        error_output("CLAUDE_SESSION_KEY not set — edit ~/.claude_usage_env")
        sys.exit(0)

    try:
        org_id = os.environ.get("CLAUDE_ORG_ID", "").strip() or discover(session_key)
        data = fetch_usage(session_key, org_id)
        swiftbar_output(data)
    except Exception as e:
        error_output(str(e))


if __name__ == "__main__":
    main()
PYTHON