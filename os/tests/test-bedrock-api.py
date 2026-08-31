#!/usr/bin/python3
import hashlib
import http.client
import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
API = ROOT / "config/includes.chroot/usr/lib/bedrock/bedrock-api"
TOKEN = "a" * 64


class UnixConnection(http.client.HTTPConnection):
    def __init__(self, path: pathlib.Path):
        super().__init__("localhost", timeout=2)
        self.path = path

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(str(self.path))


def request(socket_path: pathlib.Path, method: str, path: str, token: str | None = TOKEN):
    connection = UnixConnection(socket_path)
    headers = {} if token is None else {"Authorization": f"Bearer {token}"}
    connection.request(method, path, headers=headers)
    response = connection.getresponse()
    body = json.loads(response.read())
    connection.close()
    return response.status, body


def main() -> None:
    if not hasattr(socket, "AF_UNIX"):
        raise SystemExit("AF_UNIX support is required")
    with tempfile.TemporaryDirectory(prefix="bedrock-api-") as temporary:
        work = pathlib.Path(temporary)
        socket_path = work / "api.sock"
        tokens = work / "tokens.json"
        capabilities = work / "capabilities.json"
        tokens.write_text(json.dumps({"schema": 1, "tokens": [{
            "name": "test-client", "sha256": hashlib.sha256(TOKEN.encode()).hexdigest(),
            "created_at": "2026-08-31T00:00:00Z", "revoked": False,
        }]}), encoding="utf-8")
        capabilities.write_text(json.dumps({"schema": 1, "status": "ready"}), encoding="utf-8")
        environment = os.environ | {
            "BEDROCK_API_SOCKET": str(socket_path),
            "BEDROCK_API_TOKENS": str(tokens),
            "BEDROCK_API_CAPABILITIES": str(capabilities),
        }
        process = subprocess.Popen([sys.executable, str(API)], env=environment)
        try:
            for _ in range(50):
                if socket_path.exists():
                    break
                if process.poll() is not None:
                    raise AssertionError("API exited before creating its socket")
                time.sleep(0.05)
            else:
                raise AssertionError("API socket was not created")

            assert request(socket_path, "GET", "/api/v1/health", None) == (401, {"schema": 1, "error": "unauthorized"})
            assert request(socket_path, "GET", "/api/v1/health")[0] == 200
            assert request(socket_path, "GET", "/api/v1/virtualization/capabilities") == (200, {"schema": 1, "data": {"schema": 1, "status": "ready"}})
            assert request(socket_path, "GET", "/api/v2/health")[0] == 404
            assert request(socket_path, "POST", "/api/v1/health", None)[0] == 401
            assert request(socket_path, "POST", "/api/v1/health")[0] == 405
            tokens.write_text('{"schema":1,"tokens":[]}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/health")[0] == 401
        finally:
            process.terminate()
            process.wait(timeout=5)
    print("Bedrock local API tests passed.")


if __name__ == "__main__":
    main()
