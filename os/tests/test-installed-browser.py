#!/usr/bin/python3
"""Real Chromium + installed assets + HTTPS/API; no production credentials."""
import json
import os
import pathlib
import subprocess
import sys
import time

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
        if arguments[0] == "open":
            print((result.stdout + result.stderr)[-3000:], file=sys.stderr)
        # Neither argv nor captured output should print secret-bearing evaluations.
        raise AssertionError("installed browser command failed: " + arguments[0])
    return result


try:
    rejected = browser(["open", "https://127.0.0.1:8443/"], require_success=False)
    assert rejected.returncode != 0, "browser unexpectedly trusted the unprovisioned self-signed identity"
    if "ERR_CERT_AUTHORITY_INVALID" not in rejected.stdout + rejected.stderr:
        print((rejected.stdout + rejected.stderr)[-3000:], file=sys.stderr)
        raise AssertionError("untrusted-page rejection was not a certificate validation failure")
    browser(["close"], require_success=False)
    # Chromium's Linux NSS store explicitly trusts this self-signed server leaf.
    # The legacy location, when present, takes precedence over the M146+ default.
    # https://chromium.googlesource.com/chromium/src/+/main/docs/linux/cert_management.md
    trust = pathlib.Path.home() / ".pki/nssdb"
    trust.mkdir(parents=True, exist_ok=True)
    if not (trust / "cert9.db").exists():
        subprocess.run(["certutil", "-N", "--empty-password", "-d", "sql:" + str(trust)], check=True)
    subprocess.run(["certutil", "-A", "-d", "sql:" + str(trust), "-t", "P,,",
                    "-n", "bedrock-disposable-server", "-i", certificate], check=True)
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
    # Drive the actual controlled token field without putting the secret in argv.
    entry = """(() => {
      const input = document.querySelector('input[type="password"]');
      if (!input) throw new Error('Missing token input');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, TOKEN);
      input.dispatchEvent(new Event('input', {bubbles:true}));
      return 'INPUT_READY';
    })()""".replace("TOKEN", json.dumps(token))
    assert "INPUT_READY" in browser(["eval", "--stdin"], entry).stdout
    browser(["find", "role", "button", "click", "--name", "Connect"])
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        visible = browser(["get", "text", "body"]).stdout
        if "Connected to Bedrock" in visible:
            break
        if "Server unavailable" in visible:
            raise AssertionError("actual UI connection failed after valid token submission")
        time.sleep(0.2)
    else:
        raise AssertionError("actual UI did not finish connecting")
    assert "Your Bedrock server" in visible and "Some services need attention" in visible
    assert "Live server data available" not in visible, "partial fixture was presented as fully healthy"
    connected = browser(["snapshot", "-i"]).stdout
    assert "Refresh" in connected and 'textbox "API token"' not in connected
    browser(["screenshot", "/run/bedrock-connected-browser.png"])
    assert "BEDROCK_NO_STORAGE" in browser(["eval", "--stdin"],
        "(() => { if (localStorage.length || sessionStorage.length) throw new Error('Persisted credentials'); return 'BEDROCK_NO_STORAGE'; })()").stdout
    # A page reload discards the in-memory credential and returns to the gate.
    browser(["reload"])
    browser(["wait", "--load", "networkidle"])
    assert "Connect to your server" in browser(["snapshot", "-i"]).stdout
    print("Installed UI form passed: token submission, real partial dashboard rendering, credential not persisted, reload returns to authentication.")
    print("Installed Chromium passed: explicit TLS trust, real bundle rendering, CSP-constrained authenticated/unauthenticated API fetch, no browser storage.")
finally:
    browser(["close"], require_success=False)
