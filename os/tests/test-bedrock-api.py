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
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
API = ROOT / "config/includes.chroot/usr/lib/bedrock/bedrock-api"
BROKER = ROOT / "config/includes.chroot/usr/lib/bedrock/bedrock-action-broker"
TOKEN = "a" * 64


class UnixConnection(http.client.HTTPConnection):
    def __init__(self, path: pathlib.Path):
        super().__init__("localhost", timeout=2)
        self.path = path

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(str(self.path))


def request(socket_path: pathlib.Path, method: str, path: str, token: str | None = TOKEN, body=None, extra_headers=None):
    connection = UnixConnection(socket_path)
    headers = {} if token is None else {"Authorization": f"Bearer {token}"}
    if extra_headers:
        headers.update(extra_headers)
    payload = None if body is None else json.dumps(body).encode("utf-8")
    connection.request(method, path, body=payload, headers=headers)
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
        images = work / "images.json"
        update_policy = work / "update-policy.json"
        default_update_policy = work / "default-update-policy.json"
        nas = work / "nas.json"
        action_socket = work / "action.sock"
        action_results = work / "action-results.json"
        action_calls = work / "action-calls"
        action_helper = work / "update-helper"
        action_helper.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$BEDROCK_TEST_CALLS\"\n", encoding="utf-8")
        action_helper.chmod(0o755)
        tokens.write_text(json.dumps({"schema": 1, "tokens": [{
            "name": "test-client", "sha256": hashlib.sha256(TOKEN.encode()).hexdigest(),
            "created_at": "2026-08-31T00:00:00Z", "revoked": False,
        }]}), encoding="utf-8")
        capabilities.write_text(json.dumps({"schema": 1, "status": "ready"}), encoding="utf-8")
        hardware.write_text(json.dumps({"schema": 2, "cpu": {"architecture": "x86_64", "model": "Bedrock CPU", "logical_processors": 8, "sockets": 1, "cores_per_socket": 4, "threads_per_core": 2, "virtualization": "AMD-V", "virtualization_supported": True}, "memory": {"total_bytes": 16000000000}, "disks": [{"name": "sda", "path": "/dev/sda", "model": "Bedrock SSD", "vendor": "Bedrock", "size_bytes": 1000000000, "rotational": False, "transport": "sata", "removable": False, "serial": "must-not-leak"}], "storage_controllers": [{"address": "0000:00:17.0", "class": "sata", "description": "0000:00:17.0 SATA controller"}], "networks": [{"name": "enp1s0", "mac": "00:11:22:33:44:55", "mtu": 1500, "state": "UP", "link_type": "ether"}], "gpus": [{"name": "card0", "pci_address": "0000:01:00.0", "vendor": "AMD", "vendor_id": "0x1002", "device_id": "0x1234", "driver": "amdgpu", "iommu_group": "7", "iommu_group_devices": ["0000:01:00.0"], "boot_vga": True, "recognized_vendor": True}], "usb_devices": [{"id": "1-1"}]}), encoding="utf-8")
        storage.write_text(json.dumps({"schema": 1, "generated_unix": 100, "overall": "healthy", "read_only": True, "disks": [{"path": "/dev/sda", "serial": "private-serial", "model": "Bedrock SSD", "size_bytes": 1000000000, "transport": "sata", "smart": {"available": True, "passed": True, "temperature_c": 31, "power_on_hours": 1000, "power_mode": "ACTIVE", "command_exit": 0, "health": "healthy"}}, {"path": "/dev/sdb", "serial": None, "model": "Archive", "size_bytes": 2000000000, "transport": "sas", "smart": {"available": False, "passed": None, "temperature_c": None, "power_on_hours": None, "power_mode": "unknown", "command_exit": 1, "health": "unknown"}}], "software_raid": {"md_arrays": [{"name": "md0", "path": "/dev/md0", "level": "raid1", "state": "active", "member_pattern": "UU", "expected_members": 2, "active_members": 2, "health": "healthy", "sync": {"action": None, "percent": 0}}], "zfs": {"available": True, "pools": [{"name": "main", "size_bytes": 1000, "allocated_bytes": 400, "free_bytes": 600, "health": "ONLINE", "status": "healthy"}]}}, "hardware_raid": {"controllers": [{"address": "0000:01:00.0"}], "management_tools": [], "vendor_reports": [], "explanation": "limited"}}), encoding="utf-8")
        alerts.write_text(json.dumps({"schema": 1, "generated_unix": 101, "attention_required": True, "active_count": 1,
            "active": [{"alert_id": "disk-smart:sda", "kind": "disk-smart", "resource": "/dev/sda", "severity": "critical", "first_seen_unix": 90, "last_seen_unix": 101}]}), encoding="utf-8")
        vms.write_text(json.dumps({"schema": 1, "generated_unix": 102, "domains": [{"name": "private-name", "state": "running", "autostart": True, "vcpus": 4, "memory_mib": 8192, "snapshot_count": 2, "image_attachments": ["windows"], "network_attachments": ["private-lan"]}, {"name": "other", "state": "shut off", "autostart": False, "vcpus": 2, "memory_mib": 2048, "snapshot_count": 0, "image_attachments": [], "network_attachments": []}]}), encoding="utf-8")
        updates.write_text(json.dumps({"schema": 1, "status": "available", "checked_unix": 103, "installed_generation": 1, "available_generation": 2, "available_version": "0.6.0", "available_channel": "stable"}), encoding="utf-8")
        tasks.write_text(json.dumps({"schema": 1, "generated_unix": 104, "tasks": [{"id": "task-1", "kind": "image-import", "state": "running", "created_unix": 100, "updated_unix": 104, "progress": {"current": 25, "total": 100, "unit": "percent"}}]}), encoding="utf-8")
        audit.write_text(json.dumps({"id": "event-1", "category": "storage", "action": "scrub", "outcome": "succeeded", "occurred_unix": 99}) + "\n", encoding="utf-8")
        remote.write_text(json.dumps({"schema": 1, "devices": [{"id": "42345678-1234-4123-8123-123456789abc", "name": "Office laptop", "created_unix": 1000, "expires_unix": 2000, "revoked": False, "expired": False, "last_seen_unix": None}]}), encoding="utf-8")
        apps.write_text(json.dumps({"schema": 1, "apps": [{"id": "media", "name": "Media", "network": "bridge", "port_count": 1, "resources": {"cpus": 1, "memory_mib": 512, "pids": 128}, "update_policy": "notify", "created_unix": 100}]}), encoding="utf-8")
        backups.write_text(json.dumps({"schema": 1, "plans": [{"id": "daily", "name": "Daily", "kind": "local", "schedule": {"frequency": "daily", "hour_utc": 2, "weekday": None}, "retention": {"daily": 7, "weekly": 4, "monthly": 3}, "created_unix": 100, "last_success_unix": 200, "has_snapshot": True}]}), encoding="utf-8")
        images.write_text(json.dumps({"schema": 1, "images": [{"name": "installer", "type": "iso", "sha256": "c" * 64, "size_bytes": 4096, "converted": False}]}), encoding="utf-8")
        update_policy.write_text(json.dumps({"schema": 2, "automatic_checks": True, "setup_choice_recorded": True, "channel": "stable"}), encoding="utf-8")
        default_update_policy.write_text(json.dumps({"schema": 2, "automatic_checks": False, "setup_choice_recorded": False, "channel": "stable"}), encoding="utf-8")
        nas.write_text(json.dumps({"schema": 1, "users": [{"name": "alice", "credential_generation": 1, "created_unix": 10, "credential_rotated_unix": 13}], "groups": [{"name": "family", "members": ["alice"], "created_unix": 11}], "datasets": [{"pool": "vault", "name": "private", "path": "/private/path", "acl_subjects": ["family"]}], "shares": [{"name": "private-share"}], "snapshots": [{"name": "private-snapshot"}]}), encoding="utf-8")
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
            "BEDROCK_API_IMAGES": str(images),
            "BEDROCK_API_UPDATE_POLICY": str(update_policy),
            "BEDROCK_API_DEFAULT_UPDATE_POLICY": str(default_update_policy),
            "BEDROCK_API_NAS": str(nas),
            "BEDROCK_API_ACTION_BROKER": str(action_socket),
        }
        broker_environment = os.environ | {
            "BEDROCK_ACTION_BROKER_TEST_MODE": "1",
            "BEDROCK_ACTION_BROKER_EXPECTED_UID": str(os.getuid()),
            "BEDROCK_ACTION_BROKER_SOCKET": str(action_socket),
            "BEDROCK_ACTION_BROKER_STATE": str(action_results),
            "BEDROCK_ACTION_BROKER_UPDATE_HELPER": str(action_helper),
            "BEDROCK_TEST_CALLS": str(action_calls),
        }
        broker = subprocess.Popen([sys.executable, str(BROKER)], env=broker_environment)
        for _ in range(50):
            if action_socket.exists():
                break
            if broker.poll() is not None:
                raise AssertionError("broker exited before creating its socket")
            time.sleep(0.05)
        else:
            raise AssertionError("broker socket was not created")
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
            assert set(schema_body["paths"]) == {"/api/v1/openapi.json", "/api/v1/health", "/api/v1/dashboard", "/api/v1/tasks", "/api/v1/alerts", "/api/v1/audit", "/api/v1/apps", "/api/v1/backups", "/api/v1/hardware", "/api/v1/images", "/api/v1/remote/devices", "/api/v1/settings", "/api/v1/storage", "/api/v1/users", "/api/v1/virtualization/capabilities", "/api/v1/vms"}
            assert schema_body["security"] == [{"bearerAuth": []}]
            assert set(schema_body["paths"]["/api/v1/settings"]) == {"get", "put"}
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
            vm_status, vm_body = request(socket_path, "GET", "/api/v1/vms")
            assert vm_status == 200 and vm_body["domains"][0]["name"] == "private-name" and vm_body["domains"][0]["snapshot_count"] == 2
            image_status, image_body = request(socket_path, "GET", "/api/v1/images")
            assert image_status == 200 and image_body["images"][0]["sha256"] == "c" * 64 and "path" not in json.dumps(image_body)
            storage_status, storage_body = request(socket_path, "GET", "/api/v1/storage")
            assert storage_status == 200 and storage_body["disks"][0]["smart"]["temperature_c"] == 31 and storage_body["software_raid"]["zfs"]["pools"][0]["name"] == "main"
            assert not any(secret in json.dumps(storage_body) for secret in ["/dev/sda", "/dev/md0", "private-serial", "0000:01:00.0", "member_pattern"])
            assert request(socket_path, "GET", "/api/v1/settings") == (200, {"schema": 1, "updates": {"automatic_checks": True, "setup_choice_recorded": True, "channel": "stable", "automatic_install": False}, "telemetry_enabled": False})
            update_id = str(uuid.uuid4())
            update_body = {"schema": 1, "setting": "channel", "value": "beta", "beta_risk_acknowledged": True}
            update_headers = {"Content-Type": "application/json", "Idempotency-Key": update_id}
            assert request(socket_path, "PUT", "/api/v1/settings", body=update_body, extra_headers=update_headers) == (200, {"schema": 1, "request_id": update_id, "status": "succeeded", "replayed": False})
            assert request(socket_path, "PUT", "/api/v1/settings", body=update_body, extra_headers=update_headers)[1]["replayed"] is True
            conflict_body = update_body | {"value": "stable", "beta_risk_acknowledged": False}
            assert request(socket_path, "PUT", "/api/v1/settings", body=conflict_body, extra_headers=update_headers)[0] == 409
            assert action_calls.read_text(encoding="utf-8").splitlines() == ["channel beta I_ACCEPT_PRERELEASE_UPDATE_RISK"]
            assert request(socket_path, "PUT", "/api/v1/settings", None, update_body, update_headers)[0] == 401
            assert request(socket_path, "PUT", "/api/v1/settings", body=update_body, extra_headers={"Content-Type": "application/json"})[0] == 400
            assert request(socket_path, "PUT", "/api/v1/settings", body=update_body | {"command": "id"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            users_status, users_body = request(socket_path, "GET", "/api/v1/users")
            assert users_status == 200 and users_body["users"][0]["credential_generation"] == 1 and users_body["groups"][0]["member_count"] == 1
            assert not any(secret in json.dumps(users_body) for secret in ["/private/path", "private-share", "private-snapshot", "members", "datasets", "shares", "snapshots"])
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
            vms.write_text('{"schema":1,"generated_unix":103,"domains":[{"name":"bad name"}]}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/vms") == (503, {"schema": 1, "error": "vms-unavailable"})
            images.write_text('{"schema":1,"images":[{"name":"bad","path":"/secret"}]}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/images") == (503, {"schema": 1, "error": "images-unavailable"})
            storage.write_text('{"schema":1,"overall":"healthy"}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/storage") == (503, {"schema": 1, "error": "storage-unavailable"})
            update_policy.write_text('{"schema":2,"automatic_checks":"yes"}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/settings") == (503, {"schema": 1, "error": "settings-unavailable"})
            nas.write_text('{"schema":1,"users":[{"name":"INVALID"}],"groups":[],"datasets":[],"shares":[],"snapshots":[]}', encoding="utf-8")
            assert request(socket_path, "GET", "/api/v1/users") == (503, {"schema": 1, "error": "users-unavailable"})
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
            broker.terminate()
            broker.wait(timeout=5)
    print("Bedrock local API tests passed.")


if __name__ == "__main__":
    main()
