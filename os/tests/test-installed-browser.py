#!/usr/bin/python3
"""Real Chromium + installed assets + HTTPS/API; no production credentials."""
import json
import os
import pathlib
import subprocess
import sys

assert os.geteuid() == 0 and pathlib.Path("/.dockerenv").exists()
assert os.environ.get("BEDROCK_DISPOSABLE_SERVICE_TEST") == "1"
token = sys.stdin.read().strip()
assert len(token) == 64
base = ["agent-browser", "--session", "bedrock-acceptance", "--executable-path", "/usr/bin/chromium",
        "--args", "--no-sandbox"]  # Disposable privileged test container only, never image configuration.
certificate = "/var/lib/bedrock/web/identity/server.crt"


def browser(arguments, script=None, require_success=True):
    result = subprocess.run(base + arguments, input=script, text=True, capture_output=True, timeout=45)
    if require_success and result.returncode:
        # Neither argv nor captured output should print secret-bearing evaluations.
        raise AssertionError("installed browser command failed: " + arguments[0])
    return result


try:
    rejected = browser(["open", "https://127.0.0.1:8443/"], require_success=False)
    assert rejected.returncode != 0, "browser unexpectedly trusted the unprovisioned self-signed identity"
    browser(["close"], require_success=False)
    base += ["--ca-cert", certificate]
    browser(["open", "https://127.0.0.1:8443/"])
    browser(["wait", "--load", "networkidle"])
    snapshot = browser(["snapshot", "-i"]).stdout
    assert "Connect to your server" in snapshot and "API token" in snapshot
    browser(["screenshot", "/run/bedrock-installed-browser.png"])
    assert pathlib.Path("/run/bedrock-installed-browser.png").stat().st_size > 0
    # Exercise fetch in the actual document, under the shipped CSP and TLS policy.
    script = """(async () => {
      const denied = await fetch('/api/v1/images', {cache:'no-store'});
      const accepted = await fetch('/api/v1/images', {cache:'no-store', headers:{Authorization:'Bearer ' + TOKEN}});
      const body = await accepted.json();
      if (denied.status !== 401 || accepted.status !== 200 || body.schema !== 1) throw new Error('API boundary failed');
      if (localStorage.length || sessionStorage.length) throw new Error('Unexpected browser persistence');
      return 'BEDROCK_BROWSER_API_OK';
    })()""".replace("TOKEN", json.dumps(token))
    assert "BEDROCK_BROWSER_API_OK" in browser(["eval", "--stdin"], script).stdout
    print("Installed Chromium passed: explicit TLS trust, real bundle rendering, CSP-constrained authenticated/unauthenticated API fetch, no browser storage.")
finally:
    browser(["close"], require_success=False)
