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
        hardware = work / "hardware.json"
        storage = work / "storage.json"
        alerts = work / "alerts.json"
        vms = work / "vms.json"
        updates = work / "updates.json"
        tasks = work / "tasks.json"
        audit = work / "audit.jsonl"
        tokens.write_text(json.dumps({"schema": 1, "tokens": [{
            "name": "test-client", "sha256": hashlib.sha256(TOKEN.encode()).hexdigest(),
            "created_at": "2026-08-31T00:00:00Z", "revoked": False,
        }]}), encoding="utf-8")
        capabilities.write_text(json.dumps({"schema": 1, "status": "ready"}), encoding="utf-8")
        hardware.write_text(json.dumps({"schema": 2, "cpu": {"architecture": "x86_64", "logical_processors": 8, "virtualization_supported": True}, "memory": {"total_bytes": 16000000000}, "disks": [{"serial": "must-not-leak"}], "networks": [{}]}), encoding="utf-8")
        storage.write_text(json.dumps({"schema": 1, "generated_unix": 100, "overall": "healthy", "read_only": True, "disks": [{}, {}]}), encoding="utf-8")
        alerts.write_text(json.dumps({"schema": 1, "generated_unix": 101, "attention_required": True, "active_count": 1,
            "active": [{"alert_id": "disk-smart:sda", "kind": "disk-smart", "resource": "/dev/sda", "severity": "critical", "first_seen_unix": 90, "last_seen_unix": 101}]}), encoding="utf-8")
        vms.write_text(json.dumps({"schema": 1, "generated_unix": 102, "domains": [{"name": "private-name", "state": "running"}, {"name": "other", "state": "shut off"}]}), encoding="utf-8")
        updates.write_text(json.dumps({"schema": 1, "status": "available", "checked_unix": 103, "installed_generation": 1, "available_generation": 2, "available_version": "0.6.0", "available_channel": "stable"}), encoding="utf-8")
        tasks.write_text(json.dumps({"schema": 1, "generated_unix": 104, "tasks": [{"id": "task-1", "kind": "image-import", "state": "running", "created_unix": 100, "updated_unix": 104, "progress": {"current": 25, "total": 100, "unit": "percent"}}]}), encoding="utf-8")
        audit.write_text(json.dumps({"id": "event-1", "category": "storage", "action": "scrub", "outcome": "succeeded", "occurred_unix": 99}) + "\n", encoding="utf-8")
        environment = os.environ | {
            "BEDROCK_API_SOCKET": str(socket_path),
            "BEDROCK_API_TOKENS": str(tokens),
            "BEDROCK_API_CAPABILITIES": str(capabilities),
            "BEDROCK_API_HARDWARE": str(hardware), "BEDROCK_API_STORAGE": str(storage),
            "BEDROCK_API_ALERTS": str(alerts), "BEDROCK_API_VMS": str(vms),
            "BEDROCK_API_UPDATES": str(updates),
            "BEDROCK_API_TASKS": str(tasks), "BEDROCK_API_AUDIT": str(audit),
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
            dashboard_status, dashboard_body = request(socket_path, "GET", "/api/v1/dashboard")
            assert dashboard_status == 200 and dashboard_body["partial"] is False
            assert dashboard_body["components"]["hardware"]["data"]["disk_count"] == 1
            assert dashboard_body["components"]["vms"]["data"] == {"generated_unix": 102, "running": 1, "total": 2}
            assert "must-not-leak" not in json.dumps(dashboard_body) and "private-name" not in json.dumps(dashboard_body)
            assert request(socket_path, "GET", "/api/v1/tasks") == (200, {"schema": 1, "generated_unix": 104, "tasks": [{"id": "task-1", "kind": "image-import", "state": "running", "created_unix": 100, "updated_unix": 104, "progress": {"current": 25, "total": 100, "unit": "percent"}}]})
            alert_status, alert_body = request(socket_path, "GET", "/api/v1/alerts")
            assert alert_status == 200 and alert_body["alerts"][0]["kind"] == "disk-smart"
            assert "/dev/sda" not in json.dumps(alert_body)
            assert request(socket_path, "GET", "/api/v1/audit") == (200, {"schema": 1, "events": [{"id": "event-1", "category": "storage", "action": "scrub", "outcome": "succeeded", "occurred_unix": 99}]})
            alerts.write_text("not-json", encoding="utf-8")
            partial_status, partial_body = request(socket_path, "GET", "/api/v1/dashboard")
            assert partial_status == 200 and partial_body["partial"] is True
            assert partial_body["components"]["alerts"] == {"status": "unavailable"}
            assert partial_body["components"]["hardware"]["status"] == "available"
            assert request(socket_path, "GET", "/api/v1/alerts") == (503, {"schema": 1, "error": "alerts-unavailable"})
            tasks.write_text(json.dumps({"schema": 1, "generated_unix": 105, "tasks": [{"id": "task-2", "kind": "update", "state": "running", "created_unix": 100, "updated_unix": 105, "progress": {"current": 101, "total": 100, "unit": "percent"}}]}), encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/tasks") == (503, {"schema": 1, "error": "tasks-unavailable"})
            audit.write_text(json.dumps({"id": "event-2", "category": "auth", "action": "login", "outcome": "maybe", "occurred_unix": 105}) + "\n", encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/audit") == (503, {"schema": 1, "error": "audit-unavailable"})
            assert request(socket_path, "GET", "/api/v2/health")[0] == 404
            assert request(socket_path, "POST", "/api/v1/health", None)[0] == 401
            assert request(socket_path, "POST", "/api/v1/health")[0] == 405
            tokens.write_text('{"schema":1,"tokens":[]}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/health")[0] == 401
            tokens.write_text(json.dumps({"schema": 1, "tokens": [{
                "name": "test-client", "sha256": hashlib.sha256(TOKEN.encode()).hexdigest(),
                "created_at": "2026-08-31T00:00:00Z", "revoked": True,
            }]}), encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/health")[0] == 401
        finally:
            process.terminate()
            process.wait(timeout=5)
    print("Bedrock local API tests passed.")


if __name__ == "__main__":
    main()
