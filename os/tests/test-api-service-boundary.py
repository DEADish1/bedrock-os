#!/usr/bin/python3
"""Production UID/task boundary test; only run inside the disposable test container."""
import hashlib
import http.client
import json
import os
import pathlib
import pwd
import shutil
import socket
import stat
import subprocess
import time


def main():
    if os.environ.get("BEDROCK_DISPOSABLE_SERVICE_TEST") != "1" or not pathlib.Path("/.dockerenv").exists() or os.geteuid() != 0:
        raise SystemExit("requires the disposable root Docker test container")
    assert not any(key.endswith("TEST_MODE") for key in os.environ)
    root = pathlib.Path(__file__).resolve().parents[1] / "config/includes.chroot"
    destination = pathlib.Path("/usr/lib/bedrock")
    assert not destination.exists() and not pathlib.Path("/var/lib/bedrock").exists()
    subprocess.run(["useradd", "--system", "--user-group", "--home-dir", "/nonexistent", "bedrock-api"], check=True)
    account = pwd.getpwnam("bedrock-api")
    destination.mkdir()
    for name in ("bedrock-api", "bedrock-action-broker", "record-api-task", "create-api-token"):
        shutil.copyfile(root / "usr/lib/bedrock" / name, destination / name)
        (destination / name).chmod(0o755)
    pathlib.Path("/usr/share/bedrock").mkdir()
    shutil.copyfile(root / "usr/share/bedrock/empty-api-tokens.json", "/usr/share/bedrock/empty-api-tokens.json")
    # Provision the token before the broker, as a first-run console would.
    issued = subprocess.run([str(destination / "create-api-token"), "boundary-test"], capture_output=True, text=True, check=True)
    token = json.loads(issued.stdout)["token"]
    state = pathlib.Path("/var/lib/bedrock/api")
    assert state.stat().st_gid == account.pw_gid, "API cannot traverse a root-only token directory"
    uploads = pathlib.Path("/var/lib/bedrock/virtualization/uploads")
    uploads.mkdir(parents=True)
    os.chown(uploads, account.pw_uid, account.pw_gid)
    uploads.chmod(0o750)
    sources = state / "sources"
    sources.mkdir()
    sources.chmod(0o755)
    (sources / "images.json").write_text('{"schema":1,"images":[]}')
    for path, uid in (("/run/bedrock-api", account.pw_uid), ("/run/bedrock-action-broker", 0)):
        pathlib.Path(path).mkdir()
        os.chown(path, uid, account.pw_gid)
        os.chmod(path, 0o750)
    environment = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"}

    def command(uid, executable, *args):
        return ["setpriv", f"--reuid={uid}", f"--regid={account.pw_gid}", "--clear-groups",
                "--bounding-set=-all", "--inh-caps=-all", "--ambient-caps=-all", "--no-new-privs",
                str(destination / executable), *args]

    def request(method, path, body=None, headers=None):
        client = http.client.HTTPConnection("localhost", timeout=5)
        client.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.sock.settimeout(5)
        client.sock.connect("/run/bedrock-api/api.sock")
        try:
            client.request(method, path, body=body, headers={"Authorization": f"Bearer {token}", **(headers or {})})
            response = client.getresponse()
            return response.status, json.loads(response.read()), dict(response.getheaders())
        finally:
            client.close()

    subprocess.run(command(0, "record-api-task", "--recover"), env=environment, check=True)
    broker = subprocess.Popen(command(0, "bedrock-action-broker"), env=environment)
    api = None
    try:
        for _ in range(100):
            assert broker.poll() is None, "production broker exited"
            if pathlib.Path("/run/bedrock-action-broker/action.sock").exists():
                break
            time.sleep(0.05)
        else:
            raise AssertionError("broker did not listen")
        api = subprocess.Popen(command(account.pw_uid, "bedrock-api"), env=environment)
        for _ in range(100):
            assert api.poll() is None, "unprivileged API exited"
            try:
                if request("GET", "/api/v1/images")[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(0.05)
        else:
            raise AssertionError("unprivileged API did not become ready")
        for process, uid in ((api, account.pw_uid), (broker, 0)):
            status = dict(line.split(":", 1) for line in pathlib.Path(f"/proc/{process.pid}/status").read_text().splitlines() if ":" in line)
            assert all(int(value) == uid for value in status["Uid"].split())
            assert int(status["CapBnd"].strip(), 16) == 0
            assert status["NoNewPrivs"].strip() == "1"
        # Even root is not an authorized broker peer; only the API UID is.
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.settimeout(5)
            peer.connect("/run/bedrock-action-broker/action.sock")
            rejected = json.loads(peer.recv(4096))
            assert rejected["error"]["code"] == "unauthorized-peer"
        _, _, headers = request("GET", "/api/v1/images")
        contents = b"production-uid-upload"
        result, candidate, _ = request("PUT", "/api/v1/images/boundary/upload", contents,
            {"Content-Type": "application/octet-stream", "X-Bedrock-Image-Type": "iso", "If-Match": headers["ETag"]})
        assert result == 200, candidate
        assert (uploads / "boundary.iso").stat().st_uid == account.pw_uid
        for name in ("tasks.json", "audit.jsonl"):
            info = (state / name).stat()
            assert info.st_uid == 0 and info.st_gid == account.pw_gid and stat.S_IMODE(info.st_mode) == 0o640
            denied = subprocess.run(["setpriv", f"--reuid={account.pw_uid}", f"--regid={account.pw_gid}", "--clear-groups",
                "python3", "-c", "import sys; open(sys.argv[1], 'ab')", str(state / name)], capture_output=True, env=environment)
            assert denied.returncode != 0, "API can write privileged task state"
        denied = subprocess.run(command(account.pw_uid, "record-api-task", "--recover"), capture_output=True, env=environment)
        assert denied.returncode != 0, "task recorder allowed an unprivileged writer"
        _, _, headers = request("GET", "/api/v1/images")
        digest = hashlib.sha256(contents).hexdigest()
        result, body, _ = request("DELETE", "/api/v1/images/boundary/upload",
            json.dumps({"schema": 1, "sha256": digest, "confirmation": f"DISCARD IMAGE UPLOAD boundary {digest}"}),
            {"Content-Type": "application/json", "If-Match": headers["ETag"]})
        assert result == 200 and body["discarded"], body
        assert not list(uploads.iterdir())
        tasks = json.loads((state / "tasks.json").read_text())["tasks"]
        assert len(tasks) == 2 and all(item["state"] == "succeeded" for item in tasks)
        events = [json.loads(line) for line in (state / "audit.jsonl").read_text().splitlines()]
        assert len(events) == 2 and {item["action"] for item in events} == {"image-upload", "image-discard"}
        print("Production UID boundary passed: API unprivileged, broker root with no capabilities, peer rejection, protected state, upload/discard audit.")
    finally:
        for process in (api, broker):
            if process is not None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
