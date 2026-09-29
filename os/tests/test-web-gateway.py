#!/usr/bin/python3
"""Run inside the disposable systemd fixture while the real API is active."""
import hashlib
import http.client
import json
import os
import pathlib
import pwd
import shutil
import socket
import ssl
import subprocess
import sys
import time

assert os.environ.get("BEDROCK_DISPOSABLE_SERVICE_TEST") == "1" and pathlib.Path("/.dockerenv").exists()
assert os.geteuid() == 0
token = sys.stdin.read().strip()
assert len(token) == 64
root = pathlib.Path(__file__).resolve().parents[1] / "config/includes.chroot"
subprocess.run(["useradd", "--system", "--user-group", "--home-dir", "/nonexistent", "bedrock-web"], check=True)
for name in ("bedrock-web", "bedrock-web-identity"):
    shutil.copyfile(root / f"usr/lib/systemd/system/{name}.service", f"/etc/systemd/system/{name}.service")
helper = pathlib.Path("/usr/lib/bedrock/initialize-web-identity")
shutil.copyfile(root / "usr/lib/bedrock/initialize-web-identity", helper)
helper.chmod(0o755)
preparer = pathlib.Path("/usr/lib/bedrock/prepare-web-gateway")
shutil.copyfile(root / "usr/lib/bedrock/prepare-web-gateway", preparer)
preparer.chmod(0o755)
manager = pathlib.Path("/usr/lib/bedrock/manage-api-tokens")
shutil.copyfile(root / "usr/lib/bedrock/manage-api-tokens", manager)
manager.chmod(0o755)
pathlib.Path("/etc/bedrock").mkdir(exist_ok=True)
for name in ("web-gateway.conf", "web-proxy.conf"):
    shutil.copyfile(root / "etc/bedrock" / name, pathlib.Path("/etc/bedrock") / name)
dropin = pathlib.Path("/etc/systemd/system/nginx.service.d")
dropin.mkdir(exist_ok=True)
shutil.copyfile(root / "etc/systemd/system/nginx.service.d/bedrock.conf", dropin / "bedrock.conf")
ui = pathlib.Path("/usr/share/bedrock/management-ui")
shutil.copytree(root / "usr/share/bedrock/management-ui", ui)
manifest = json.loads((ui / "build-manifest.json").read_text())
subprocess.run(["systemctl", "daemon-reload"], check=True)
subprocess.run(["systemctl", "stop", "nginx"], check=True)
subprocess.run(["systemctl", "start", "nginx"], check=True)
assert subprocess.run(["systemctl", "is-active", "--quiet", "nginx"]).returncode != 0
try:
    with socket.create_connection(("127.0.0.1", 80), timeout=1):
        raise AssertionError("distribution HTTP listener is still active")
except ConnectionRefusedError:
    pass
subprocess.run(["systemctl", "start", "bedrock-web"], check=True)
certificate = pathlib.Path("/var/lib/bedrock/web/identity/server.crt")
context = ssl.create_default_context(cafile=str(certificate))


def request(method, path, body=None, headers=None):
    connection = http.client.HTTPSConnection("127.0.0.1", 8443, context=context, timeout=5)
    try:
        connection.request(method, path, body=body, headers=headers or {})
        result = connection.getresponse()
        return result.status, result.read(), dict(result.getheaders())
    finally:
        connection.close()


def wait_ready():
    for _ in range(100):
        try:
            if request("GET", "/")[0] == 200:
                return
        except OSError:
            pass
        time.sleep(0.05)
    raise AssertionError("HTTPS gateway did not start")


try:
    wait_ready()
    status, body, headers = request("GET", "/")
    assert status == 200 and body == (ui / "index.html").read_bytes()
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert headers["Referrer-Policy"] == "no-referrer"
    assert "frame-ancestors 'none'" in headers["Content-Security-Policy"]
    for asset in manifest["files"]:
        status, payload, asset_headers = request("GET", "/" + asset["path"])
        assert status == 200 and len(payload) == asset["size_bytes"]
        assert hashlib.sha256(payload).hexdigest() == asset["sha256"], "gateway changed an installed UI asset"
        assert asset_headers["X-Content-Type-Options"] == "nosniff"
        if asset["path"].endswith(".js"):
            assert "javascript" in asset_headers["Content-Type"]
        if asset["path"].endswith(".css"):
            assert asset_headers["Content-Type"].startswith("text/css")
    auth = {"Authorization": f"Bearer {token}", "Origin": "https://127.0.0.1:8443", "Sec-Fetch-Site": "same-origin"}
    assert request("GET", "/api/v1/images")[0] == 401
    assert request("GET", "/api/v1/images", headers={**auth, "Authorization": "Bearer " + "0" * 64})[0] == 401
    status, body, headers = request("GET", "/api/v1/images", headers=auth)
    assert status == 200 and json.loads(body)["schema"] == 1 and "ETag" in headers
    replacement = json.loads(subprocess.check_output(
        ["/usr/lib/bedrock/create-api-token", "gateway-replacement"], text=True))["token"]
    replacement_auth = {**auth, "Authorization": f"Bearer {replacement}"}
    assert request("GET", "/api/v1/images", headers=replacement_auth)[0] == 200
    subprocess.run([str(manager), "revoke", "gateway-replacement"], check=True, stdout=subprocess.DEVNULL)
    assert request("GET", "/api/v1/images", headers=replacement_auth)[0] == 401
    renewed = json.loads(subprocess.check_output(
        ["/usr/lib/bedrock/create-api-token", "gateway-replacement"], text=True))["token"]
    assert renewed != replacement
    assert request("GET", "/api/v1/images", headers={**auth, "Authorization": f"Bearer {renewed}"})[0] == 200
    assert request("GET", "/api/v1/images", headers=replacement_auth)[0] == 401
    subprocess.run([str(manager), "revoke", "gateway-replacement"], check=True, stdout=subprocess.DEVNULL)
    assert request("GET", "/api/v1/images", headers=auth)[0] == 200
    del replacement, replacement_auth, renewed
    assert request("GET", "/api/v1/images", headers={**auth, "Origin": "https://attacker.invalid"})[0] == 403
    assert request("GET", "/api/v1/images", headers={**auth, "Origin": "null"})[0] == 403
    assert request("GET", "/api/v1/images", headers={**auth, "Sec-Fetch-Site": "cross-site"})[0] == 403
    assert request("GET", "/api/v1/images", headers={**auth, "Host": "attacker.invalid:8443"})[0] == 421
    assert request("GET", "/.git/config")[0] == 404
    assert request("GET", "/build-manifest.json")[0] == 404
    assert request("GET", "/var/lib/bedrock/api/tokens.json")[0] == 404
    assert request("POST", "/api/v1/settings", b"x" * 65537, auth)[0] == 413
    # Exercise mutations through nginx, including an upload above the ordinary 64 KiB limit.
    task_file = pathlib.Path("/var/lib/bedrock/api/tasks.json")
    audit_file = task_file.with_name("audit.jsonl")
    tasks_before = len(json.loads(task_file.read_text())["tasks"])
    events_before = len(audit_file.read_text().splitlines())
    upload_path = "/api/v1/images/gateway-upload/upload"
    _, _, before_headers = request("GET", "/api/v1/images", headers=auth)
    upload_headers = {**auth, "Content-Type": "application/octet-stream", "X-Bedrock-Image-Type": "iso", "If-Match": before_headers["ETag"]}
    assert request("PUT", upload_path, b"denied", {**upload_headers, "Authorization": "Bearer " + "0" * 64})[0] == 401
    assert request("PUT", upload_path, b"stale", {**upload_headers, "If-Match": '"stale"'})[0] == 412
    payload = b"gateway-streaming-acceptance\n" * 3000
    assert len(payload) > 65536
    assert request("PUT", upload_path, payload, upload_headers)[0] == 200
    staged = pathlib.Path("/var/lib/bedrock/virtualization/uploads/gateway-upload.iso")
    assert staged.read_bytes() == payload
    digest = hashlib.sha256(payload).hexdigest()
    _, _, refreshed = request("GET", "/api/v1/images", headers=auth)
    assert refreshed["ETag"] != before_headers["ETag"]
    discard = {"schema": 1, "sha256": digest, "confirmation": f"DISCARD IMAGE UPLOAD gateway-upload {digest}"}
    discard_headers = {**auth, "Content-Type": "application/json", "If-Match": refreshed["ETag"]}
    assert request("DELETE", upload_path, json.dumps(discard), {**discard_headers, "If-Match": before_headers["ETag"]})[0] == 412
    assert request("DELETE", upload_path, json.dumps({**discard, "confirmation": "wrong"}), discard_headers)[0] == 400
    assert staged.read_bytes() == payload
    assert request("DELETE", upload_path, json.dumps(discard), discard_headers)[0] == 200
    assert not staged.exists()
    assert request("DELETE", upload_path, json.dumps(discard), discard_headers)[0] == 412
    assert len(json.loads(task_file.read_text())["tasks"]) == tasks_before + 2
    events = [json.loads(line) for line in audit_file.read_text().splitlines()]
    assert len(events) == events_before + 2
    assert {event["action"] for event in events[-2:]} == {"image-upload", "image-discard"}
    websocket = {**auth, "Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Version": "13",
                 "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==", "Sec-WebSocket-Protocol": "binary"}
    assert request("GET", "/api/v1/vms/guest/console", headers=websocket)[0] == 400
    assert request("GET", "/api/v1/vms/guest/console", headers={**websocket, "Origin": "https://attacker.invalid"})[0] == 403
    pid = int(subprocess.check_output(["systemctl", "show", "--property=MainPID", "--value", "bedrock-web"]))
    process = dict(line.split(":", 1) for line in pathlib.Path(f"/proc/{pid}/status").read_text().splitlines() if ":" in line)
    assert all(int(value) == pwd.getpwnam("bedrock-web").pw_uid for value in process["Uid"].split())
    assert int(process["CapBnd"].strip(), 16) == 0 and process["NoNewPrivs"].strip() == "1"
    identity_before = hashlib.sha256(certificate.read_bytes()).hexdigest()
    subprocess.run(["systemctl", "restart", "bedrock-web"], check=True)
    wait_ready()
    assert request("GET", "/api/v1/images", headers=auth)[0] == 200
    assert hashlib.sha256(certificate.read_bytes()).hexdigest() == identity_before
    # Check access with the running service's mount namespace and UID/groups.
    pid = int(subprocess.check_output(["systemctl", "show", "--property=MainPID", "--value", "bedrock-web"]))
    account = pwd.getpwnam("bedrock-web")
    sandbox_reader = [
        "nsenter", f"--target={pid}", "--mount", "setpriv",
        f"--reuid={account.pw_uid}", f"--regid={account.pw_gid}", "--groups=bedrock-api",
        "python3", "-c", "import pathlib,sys; pathlib.Path(sys.argv[1]).open('rb').close()",
    ]
    # Positive control prevents a broken nsenter/setpriv invocation from passing denials.
    subprocess.run(sandbox_reader + ["/run/credentials/bedrock-web.service/tls-cert"], check=True)
    for protected in ("/var/lib/bedrock/web/identity/server.key", "/var/lib/bedrock/api/tokens.json"):
        denied = subprocess.run(sandbox_reader + [protected], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert denied.returncode != 0, f"gateway UID can read protected state: {protected}"
    # A bad persistent identity must fail closed without replacing owner trust.
    subprocess.run(["systemctl", "stop", "bedrock-web"], check=True)
    private_key = certificate.with_name("server.key")
    saved_key = private_key.with_name("server.key.saved")
    private_key.rename(saved_key)
    try:
        private_key.symlink_to(saved_key.name)
        assert subprocess.run([str(helper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
        assert private_key.is_symlink() and hashlib.sha256(certificate.read_bytes()).hexdigest() == identity_before
    finally:
        private_key.unlink()
        saved_key.rename(private_key)
    for unsafe_mode in (0o640, 0o644):
        private_key.chmod(unsafe_mode)
        try:
            assert subprocess.run([str(helper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
            assert private_key.stat().st_mode & 0o777 == unsafe_mode
            assert hashlib.sha256(certificate.read_bytes()).hexdigest() == identity_before
        finally:
            private_key.chmod(0o600)
    os.link(private_key, saved_key)
    try:
        assert subprocess.run([str(helper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
    finally:
        saved_key.unlink()
    subprocess.run(["systemctl", "start", "bedrock-web"], check=True)
    wait_ready()
    for scenario in ("issue", "decline", "failure"):
        subprocess.run(["python3", str(pathlib.Path(__file__).with_name("test-management-console.py")), scenario], check=True, timeout=45)
    subprocess.run(["python3", str(pathlib.Path(__file__).with_name("test-installed-browser.py"))], input=token, text=True, check=True, timeout=180)
    print("HTTPS gateway passed: trusted local TLS, real API authorization, origin/host checks, request limits, no default HTTP site, stable identity and unprivileged service.")
finally:
    subprocess.run(["systemctl", "stop", "bedrock-web"], check=True)
