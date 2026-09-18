#!/usr/bin/env python3
# <xbar.title>Dexcom Glucose</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.author>omarchy-dexcom-bar contributors</xbar.author>
# <xbar.author.github>mojeska</xbar.author.github>
# <xbar.desc>Shows current Dexcom Share blood glucose in the menu bar, colored purple above a high threshold and red below a low threshold.</xbar.desc>
# <xbar.dependencies>python3</xbar.dependencies>
#
# macOS port of the Omarchy dexcom-glucose bar widget, for xbar
# (https://xbarapp.com/) or SwiftBar. Self-contained: unlike the Omarchy
# version there's no separate plugin+helper split, it's just this one
# script. Drop it in your xbar plugins folder and make it executable:
#   chmod +x dexcom-glucose.60s.py
# The ".60s." in the filename is how xbar knows to run it every 60 seconds.

import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "dexcom-bar"
CONFIG_PATH = CONFIG_DIR / "dexcom.json"
STATE_PATH = CONFIG_DIR / "state.json"

DEFAULT_CONFIG = {
    "username": "",
    "password": "",
    "region": "us",
    "highThreshold": 180,
    "lowThreshold": 70,
}

# Same application id every Dexcom Share client (pydexcom, xDrip, Nightscout
# bridges) registers with -- Dexcom Share has no public app-registration flow.
APPLICATION_ID = "d8665ade-9673-4e27-9ff6-92db4ce13d13"

BASE_URLS = {
    "us": "https://share2.dexcom.com/ShareWebServices/Services",
    "ous": "https://shareous1.dexcom.com/ShareWebServices/Services",
}

TREND_ARROWS = {
    "DoubleUp": "↑↑",
    "SingleUp": "↑",
    "FortyFiveUp": "↗",
    "Flat": "→",
    "FortyFiveDown": "↘",
    "SingleDown": "↓",
    "DoubleDown": "↓↓",
    "NotComputable": "?",
    "RateOutOfRange": "?",
}

# Dexcom Share error codes that mean the credentials themselves are wrong,
# as opposed to a transient network/server problem. Repeatedly retrying
# these looks like a brute-force attempt from Dexcom's side, so after a few
# in a row we stop hitting the API until the config file is actually edited.
AUTH_ERROR_CODES = {
    "AccountPasswordInvalid",
    "AccountPasswordInvalidLegacy",
    "SSO_AuthenticateAccountNotFound",
    "SSO_AuthenticateMaxAttemptsExceeded",
    "AccountNotFound",
    "AccountLockedOut",
    "InvalidArgument",
}
MAX_CONSECUTIVE_AUTH_FAILURES = 3
TIMEOUT = 8


def normalize_username(username, region):
    # A bare 10-digit US number is rejected by Dexcom Share unless it carries
    # the country code -- confirmed against a real account that this alone
    # produces the same generic AccountPasswordInvalid error as an actually
    # wrong password, with no other symptom to tell them apart.
    stripped = username.strip()
    if region == "us" and re.fullmatch(r"\d{10}", stripped):
        return "+1" + stripped
    return username


def ensure_config():
    if CONFIG_PATH.exists():
        return
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n", encoding="utf-8")
    CONFIG_PATH.chmod(0o600)


def load_config():
    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if isinstance(config, dict) and isinstance(config.get("username"), str):
        config["username"] = normalize_username(config["username"], str(config.get("region", "us")).lower())
    return config


def load_state():
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"consecutiveAuthFailures": 0, "configMtime": None}


def save_state(state):
    try:
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        STATE_PATH.write_text(json.dumps(state), encoding="utf-8")
    except OSError:
        pass


def post_json(url, body):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def dexcom_error_code(http_error):
    try:
        body = json.loads(http_error.read().decode("utf-8", errors="replace"))
        return str(body.get("Code", ""))
    except (json.JSONDecodeError, OSError, AttributeError):
        return ""


def parse_dexcom_date(value):
    match = re.search(r"\((\d+)", str(value or ""))
    if not match:
        return None
    return int(match.group(1)) / 1000.0


def fetch_reading():
    """Returns a result dict, mirroring omarchy-dexcom-status's JSON shape."""
    config = load_config()
    if not config or not config.get("username") or not config.get("password"):
        return {"ok": False, "error": "not configured"}

    config_mtime = CONFIG_PATH.stat().st_mtime
    state = load_state()
    if state.get("configMtime") != config_mtime:
        state = {"consecutiveAuthFailures": 0, "configMtime": config_mtime}
        save_state(state)

    if state.get("consecutiveAuthFailures", 0) >= MAX_CONSECUTIVE_AUTH_FAILURES:
        return {"ok": False, "error": "login rejected repeatedly -- edit dexcom.json to retry"}

    region = str(config.get("region", "us")).lower()
    base_url = BASE_URLS.get(region, BASE_URLS["us"])
    high = config.get("highThreshold", 180)
    low = config.get("lowThreshold", 70)

    def auth_failure(reason):
        state["consecutiveAuthFailures"] = state.get("consecutiveAuthFailures", 0) + 1
        state["configMtime"] = config_mtime
        save_state(state)
        return {"ok": False, "error": "login failed: " + reason}

    # Two-step login: AuthenticatePublisherAccount resolves the account name
    # to an internal account id, then LoginPublisherAccountById exchanges
    # that id + password for a session id. The older single-step
    # LoginPublisherAccountByName call is unreliable for some accounts even
    # with a correct password.
    try:
        account_id = post_json(
            base_url + "/General/AuthenticatePublisherAccount",
            {"accountName": config["username"], "password": config["password"], "applicationId": APPLICATION_ID},
        )
    except urllib.error.HTTPError as e:
        code = dexcom_error_code(e)
        if code in AUTH_ERROR_CODES:
            return auth_failure(code)
        return {"ok": False, "error": "authenticate failed (HTTP " + str(e.code) + (": " + code if code else "") + ")"}
    except (urllib.error.URLError, TimeoutError, OSError):
        return {"ok": False, "error": "authenticate failed (network)"}
    except json.JSONDecodeError:
        return {"ok": False, "error": "authenticate failed (bad response)"}

    if not account_id or account_id == "00000000-0000-0000-0000-000000000000":
        return auth_failure("empty account id")

    try:
        session_id = post_json(
            base_url + "/General/LoginPublisherAccountById",
            {"accountId": account_id, "password": config["password"], "applicationId": APPLICATION_ID},
        )
    except urllib.error.HTTPError as e:
        code = dexcom_error_code(e)
        if code in AUTH_ERROR_CODES:
            return auth_failure(code)
        return {"ok": False, "error": "login failed (HTTP " + str(e.code) + (": " + code if code else "") + ")"}
    except (urllib.error.URLError, TimeoutError, OSError):
        return {"ok": False, "error": "login failed (network)"}
    except json.JSONDecodeError:
        return {"ok": False, "error": "login failed (bad response)"}

    if not session_id or session_id == "00000000-0000-0000-0000-000000000000":
        return auth_failure("empty session")

    if state.get("consecutiveAuthFailures", 0) > 0:
        save_state({"consecutiveAuthFailures": 0, "configMtime": config_mtime})

    try:
        readings = post_json(
            base_url + "/Publisher/ReadPublisherLatestGlucoseValues",
            {"sessionId": session_id, "minutes": 1440, "maxCount": 1},
        )
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
        return {"ok": False, "error": "reading fetch failed (network)"}
    except json.JSONDecodeError:
        return {"ok": False, "error": "reading fetch failed (bad response)"}

    if not readings:
        return {"ok": False, "error": "no recent readings -- add an active follower in the Dexcom app"}

    latest = readings[0]
    mgdl = latest.get("Value")
    trend = latest.get("Trend", "")
    timestamp = parse_dexcom_date(latest.get("WT"))
    minutes_ago = int((time.time() - timestamp) / 60) if timestamp else None

    if mgdl is None:
        return {"ok": False, "error": "no glucose value in reading"}

    level = "high" if mgdl >= high else "low" if mgdl <= low else "normal"
    return {
        "ok": True,
        "mgdl": mgdl,
        "trend": trend,
        "trendArrow": TREND_ARROWS.get(trend, ""),
        "level": level,
        "minutesAgo": minutes_ago,
    }


def open_config_item():
    print("Edit config… | bash=/usr/bin/open param1=-t param2=" + str(CONFIG_PATH) + " terminal=false")


def render(result):
    if not result["ok"] and result["error"] == "not configured":
        print("Dexcom")
        print("---")
        print("Not configured")
        open_config_item()
        return

    if not result["ok"]:
        print("Dexcom ⚠")
        print("---")
        print(result["error"])
        print("Refresh | refresh=true")
        open_config_item()
        return

    mgdl = result["mgdl"]
    level = result["level"]
    color = "orange" if level == "high" else "red" if level == "low" else ""
    stale = result["minutesAgo"] is not None and result["minutesAgo"] > 20

    label = str(round(mgdl)) + result["trendArrow"]
    style = (" | color=" + color) if color else ""
    if stale:
        style += (" " if style else " | ") + "font=Menlo-Italic"
    print(label + style)
    print("---")

    age = "" if result["minutesAgo"] is None else (str(result["minutesAgo"]) + "m ago")
    detail = str(round(mgdl)) + " mg/dL · " + (result["trend"] or "unknown trend")
    if age:
        detail += " · " + age
    print(detail)
    if stale:
        print("Reading is stale (>20m old)")
    print("Refresh | refresh=true")
    open_config_item()


def main():
    ensure_config()
    render(fetch_reading())


if __name__ == "__main__":
    main()
