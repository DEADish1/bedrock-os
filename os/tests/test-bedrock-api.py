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
        openapi = ROOT / "config/includes.chroot/usr/share/bedrock/api/openapi-v1.json"
        remote = work / "remote.json"
        apps = work / "apps.json"
        backups = work / "backups.json"
        tokens.write_text(json.dumps({"schema": 1, "tokens": [{
            "name": "test-client", "sha256": hashlib.sha256(TOKEN.encode()).hexdigest(),
            "created_at": "2026-08-31T00:00:00Z", "revoked": False,
        }]}), encoding="utf-8")
        capabilities.write_text(json.dumps({"schema": 1, "status": "ready"}), encoding="utf-8")
        hardware.write_text(json.dumps({"schema": 2, "cpu": {"architecture": "x86_64", "model": "Bedrock CPU", "logical_processors": 8, "sockets": 1, "cores_per_socket": 4, "threads_per_core": 2, "virtualization": "AMD-V", "virtualization_supported": True}, "memory": {"total_bytes": 16000000000}, "disks": [{"name": "sda", "path": "/dev/sda", "model": "Bedrock SSD", "vendor": "Bedrock", "size_bytes": 1000000000, "rotational": False, "transport": "sata", "removable": False, "serial": "must-not-leak"}], "storage_controllers": [{"address": "0000:00:17.0", "class": "sata", "description": "0000:00:17.0 SATA controller"}], "networks": [{"name": "enp1s0", "mac": "00:11:22:33:44:55", "mtu": 1500, "state": "UP", "link_type": "ether"}], "gpus": [{"name": "card0", "pci_address": "0000:01:00.0", "vendor": "AMD", "vendor_id": "0x1002", "device_id": "0x1234", "driver": "amdgpu", "iommu_group": "7", "iommu_group_devices": ["0000:01:00.0"], "boot_vga": True, "recognized_vendor": True}], "usb_devices": [{"id": "1-1"}]}), encoding="utf-8")
        storage.write_text(json.dumps({"schema": 1, "generated_unix": 100, "overall": "healthy", "read_only": True, "disks": [{}, {}]}), encoding="utf-8")
        alerts.write_text(json.dumps({"schema": 1, "generated_unix": 101, "attention_required": True, "active_count": 1,
            "active": [{"alert_id": "disk-smart:sda", "kind": "disk-smart", "resource": "/dev/sda", "severity": "critical", "first_seen_unix": 90, "last_seen_unix": 101}]}), encoding="utf-8")
        vms.write_text(json.dumps({"schema": 1, "generated_unix": 102, "domains": [{"name": "private-name", "state": "running"}, {"name": "other", "state": "shut off"}]}), encoding="utf-8")
        updates.write_text(json.dumps({"schema": 1, "status": "available", "checked_unix": 103, "installed_generation": 1, "available_generation": 2, "available_version": "0.6.0", "available_channel": "stable"}), encoding="utf-8")
        tasks.write_text(json.dumps({"schema": 1, "generated_unix": 104, "tasks": [{"id": "task-1", "kind": "image-import", "state": "running", "created_unix": 100, "updated_unix": 104, "progress": {"current": 25, "total": 100, "unit": "percent"}}]}), encoding="utf-8")
        audit.write_text(json.dumps({"id": "event-1", "category": "storage", "action": "scrub", "outcome": "succeeded", "occurred_unix": 99}) + "\n", encoding="utf-8")
        remote.write_text(json.dumps({"schema": 1, "devices": [{"id": "42345678-1234-4123-8123-123456789abc", "name": "Office laptop", "created_unix": 1000, "expires_unix": 2000, "revoked": False, "expired": False, "last_seen_unix": None}]}), encoding="utf-8")
        apps.write_text(json.dumps({"schema": 1, "apps": [{"id": "media", "name": "Media", "network": "bridge", "port_count": 1, "resources": {"cpus": 1, "memory_mib": 512, "pids": 128}, "update_policy": "notify", "created_unix": 100}]}), encoding="utf-8")
        backups.write_text(json.dumps({"schema": 1, "plans": [{"id": "daily", "name": "Daily", "kind": "local", "schedule": {"frequency": "daily", "hour_utc": 2, "weekday": None}, "retention": {"daily": 7, "weekly": 4, "monthly": 3}, "created_unix": 100, "last_success_unix": 200, "has_snapshot": True}]}), encoding="utf-8")
        environment = os.environ | {
            "BEDROCK_API_SOCKET": str(socket_path),
            "BEDROCK_API_TOKENS": str(tokens),
            "BEDROCK_API_CAPABILITIES": str(capabilities),
            "BEDROCK_API_HARDWARE": str(hardware), "BEDROCK_API_STORAGE": str(storage),
            "BEDROCK_API_ALERTS": str(alerts), "BEDROCK_API_VMS": str(vms),
            "BEDROCK_API_UPDATES": str(updates),
            "BEDROCK_API_TASKS": str(tasks), "BEDROCK_API_AUDIT": str(audit),
            "BEDROCK_API_OPENAPI": str(openapi),
            "BEDROCK_API_REMOTE": str(remote),
            "BEDROCK_API_APPS": str(apps), "BEDROCK_API_BACKUPS": str(backups),
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
            schema_status, schema_body = request(socket_path, "GET", "/api/v1/openapi.json")
            assert schema_status == 200 and schema_body["openapi"] == "3.1.0"
            assert set(schema_body["paths"]) == {"/api/v1/openapi.json", "/api/v1/health", "/api/v1/dashboard", "/api/v1/tasks", "/api/v1/alerts", "/api/v1/audit", "/api/v1/apps", "/api/v1/backups", "/api/v1/hardware", "/api/v1/remote/devices", "/api/v1/virtualization/capabilities"}
            assert schema_body["security"] == [{"bearerAuth": []}]
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
            remote_status, remote_body = request(socket_path, "GET", "/api/v1/remote/devices")
            assert remote_status == 200 and remote_body["devices"][0]["name"] == "Office laptop"
            assert "public_key" not in json.dumps(remote_body) and "sha256" not in json.dumps(remote_body)
            app_status, app_body = request(socket_path, "GET", "/api/v1/apps")
            assert app_status == 200 and app_body["apps"][0]["id"] == "media"
            assert "image" not in json.dumps(app_body) and "digest" not in json.dumps(app_body)
            backup_status, backup_body = request(socket_path, "GET", "/api/v1/backups")
            assert backup_status == 200 and backup_body["plans"][0]["has_snapshot"] is True
            assert "source" not in json.dumps(backup_body) and "repository" not in json.dumps(backup_body) and "last_snapshot" not in json.dumps(backup_body)
            hardware_status, hardware_body = request(socket_path, "GET", "/api/v1/hardware")
            assert hardware_status == 200 and hardware_body["cpu"]["model"] == "Bedrock CPU" and hardware_body["usb_device_count"] == 1
            assert not any(secret in json.dumps(hardware_body) for secret in ["must-not-leak", "/dev/sda", "00:11:22:33:44:55", "0000:01:00.0", "0x1002"])
            alerts.write_text("not-json", encoding="utf-8")
            partial_status, partial_body = request(socket_path, "GET", "/api/v1/dashboard")
            assert partial_status == 200 and partial_body["partial"] is True
            assert partial_body["components"]["alerts"] == {"status": "unavailable"}
            assert partial_body["components"]["hardware"]["status"] == "available"
            assert request(socket_path, "GET", "/api/v1/alerts") == (503, {"schema": 1, "error": "alerts-unavailable"})
            alerts.unlink()
            alerts.symlink_to(hardware)
            assert request(socket_path, "GET", "/api/v1/alerts") == (503, {"schema": 1, "error": "alerts-unavailable"})
            tasks.write_text(json.dumps({"schema": 1, "generated_unix": 105, "tasks": [{"id": "task-2", "kind": "update", "state": "running", "created_unix": 100, "updated_unix": 105, "progress": {"current": 101, "total": 100, "unit": "percent"}}]}), encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/tasks") == (503, {"schema": 1, "error": "tasks-unavailable"})
            audit.write_text(json.dumps({"id": "event-2", "category": "auth", "action": "login", "outcome": "maybe", "occurred_unix": 105}) + "\n", encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/audit") == (503, {"schema": 1, "error": "audit-unavailable"})
            audit.unlink()
            audit.symlink_to(tokens)
            assert request(socket_path, "GET", "/api/v1/audit") == (503, {"schema": 1, "error": "audit-unavailable"})
            apps.write_text('{"schema":1,"apps":[{"id":"Bad ID"}]}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/apps") == (503, {"schema": 1, "error": "apps-unavailable"})
            backups.write_text('{"schema":1,"plans":[]}', encoding="utf-8")
            backups.unlink()
            backups.symlink_to(tokens)
            assert request(socket_path, "GET", "/api/v1/backups") == (503, {"schema": 1, "error": "backups-unavailable"})
            hardware.write_text('{"schema":2,"cpu":{}}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/hardware") == (503, {"schema": 1, "error": "hardware-unavailable"})
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
