#!/usr/bin/python3
import hashlib
import http.client
import json
import os
import pathlib
import re
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


def validate_openapi(value: object, schema: dict, document: dict, location: str = "response") -> None:
    if "$ref" in schema:
        prefix = "#/components/schemas/"
        assert schema["$ref"].startswith(prefix), f"{location}: unsupported schema reference"
        return validate_openapi(value, document["components"]["schemas"][schema["$ref"][len(prefix):]], document, location)
    if "oneOf" in schema:
        matches = 0
        for candidate in schema["oneOf"]:
            try:
                validate_openapi(value, candidate, document, location)
                matches += 1
            except AssertionError:
                pass
        assert matches == 1, f"{location}: expected exactly one oneOf match, got {matches}"
    if "const" in schema:
        assert value == schema["const"] and type(value) is type(schema["const"]), f"{location}: const mismatch"
    if "enum" in schema:
        assert any(value == item and type(value) is type(item) for item in schema["enum"]), f"{location}: enum mismatch"
    expected = schema.get("type")
    if expected is not None:
        expected_types = [expected] if isinstance(expected, str) else expected
        checks = {
            "null": value is None,
            "boolean": type(value) is bool,
            "integer": type(value) is int,
            "number": type(value) in {int, float},
            "string": isinstance(value, str),
            "array": isinstance(value, list),
            "object": isinstance(value, dict),
        }
        assert any(checks[item] for item in expected_types), f"{location}: expected {expected_types}, got {type(value).__name__}"
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        missing = set(schema.get("required", [])) - set(value)
        assert not missing, f"{location}: missing required fields {sorted(missing)}"
        if schema.get("additionalProperties") is False:
            extra = set(value) - set(properties)
            assert not extra, f"{location}: unexpected fields {sorted(extra)}"
        for key, child in value.items():
            if key in properties:
                validate_openapi(child, properties[key], document, f"{location}.{key}")
    if isinstance(value, list):
        assert len(value) >= schema.get("minItems", 0), f"{location}: too few items"
        assert len(value) <= schema.get("maxItems", len(value)), f"{location}: too many items"
        if schema.get("uniqueItems"):
            canonical = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            assert len(canonical) == len(set(canonical)), f"{location}: duplicate items"
        if "items" in schema:
            for index, child in enumerate(value):
                validate_openapi(child, schema["items"], document, f"{location}[{index}]")
    if isinstance(value, str):
        assert len(value) >= schema.get("minLength", 0), f"{location}: string is too short"
        assert len(value) <= schema.get("maxLength", len(value)), f"{location}: string is too long"
        if "pattern" in schema:
            assert re.fullmatch(schema["pattern"], value), f"{location}: pattern mismatch"
        if schema.get("format") == "uuid":
            parsed = uuid.UUID(value)
            assert str(parsed) == value and parsed.version == 4, f"{location}: UUID is not canonical v4"
    if type(value) in {int, float}:
        assert value >= schema.get("minimum", value), f"{location}: below minimum"
        assert value <= schema.get("maximum", value), f"{location}: above maximum"
        if "multipleOf" in schema:
            quotient = value / schema["multipleOf"]
            assert abs(quotient - round(quotient)) < 1e-9, f"{location}: invalid multiple"


def validate_documented_response(document: dict, method: str, path: str, value: object) -> None:
    schema = document["paths"][path][method]["responses"]["200"]["content"]["application/json"]["schema"]
    validate_openapi(value, schema, document, f"{method.upper()} {path}")


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
        action_task_state = work / "action-task-state"
        action_helper = work / "update-helper"
        action_helper.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$BEDROCK_TEST_CALLS\"\n", encoding="utf-8")
        action_helper.chmod(0o755)
        vm_action_helper = work / "vm-helper"
        vm_action_calls = work / "vm-action-calls"
        vm_action_requests = work / "vm-action-requests"
        vm_action_helper.write_text("#!/bin/sh\ncat \"$1\" >> \"$BEDROCK_VM_ACTION_CALLS\"\n", encoding="utf-8")
        vm_action_helper.chmod(0o755)
        snapshot_action_helper = work / "snapshot-helper"
        snapshot_action_calls = work / "snapshot-action-calls"
        snapshot_action_helper.write_text("#!/bin/sh\ncat \"$1\" >> \"$BEDROCK_SNAPSHOT_ACTION_CALLS\"\n", encoding="utf-8")
        snapshot_action_helper.chmod(0o755)
        admin_action_helper = work / "admin-helper"
        admin_action_calls = work / "admin-action-calls"
        vm_definitions = work / "vm-definitions"
        vm_definitions.mkdir()
        (vm_definitions / "test-vm.xml").write_text("<domain/>\n", encoding="utf-8")
        admin_action_helper.write_text("#!/bin/sh\ncat \"$1\" >> \"$BEDROCK_VM_ADMIN_CALLS\"\n", encoding="utf-8")
        admin_action_helper.chmod(0o755)
        tokens.write_text(json.dumps({"schema": 1, "tokens": [{
            "name": "test-client", "sha256": hashlib.sha256(TOKEN.encode()).hexdigest(),
            "created_at": "2026-08-31T00:00:00Z", "revoked": False,
        }]}), encoding="utf-8")
        capabilities.write_text(json.dumps({"schema": 1, "status": "ready"}), encoding="utf-8")
        hardware.write_text(json.dumps({"schema": 2, "cpu": {"architecture": "x86_64", "model": "Bedrock CPU", "logical_processors": 8, "sockets": 1, "cores_per_socket": 4, "threads_per_core": 2, "virtualization": "AMD-V", "virtualization_supported": True}, "memory": {"total_bytes": 16000000000}, "disks": [{"name": "sda", "path": "/dev/sda", "model": "Bedrock SSD", "vendor": "Bedrock", "size_bytes": 1000000000, "rotational": False, "transport": "sata", "removable": False, "serial": "must-not-leak"}], "storage_controllers": [{"address": "0000:00:17.0", "class": "sata", "description": "0000:00:17.0 SATA controller"}], "networks": [{"name": "enp1s0", "mac": "00:11:22:33:44:55", "mtu": 1500, "state": "UP", "link_type": "ether"}], "gpus": [{"name": "card0", "pci_address": "0000:01:00.0", "vendor": "AMD", "vendor_id": "0x1002", "device_id": "0x1234", "driver": "amdgpu", "iommu_group": "7", "iommu_group_devices": ["0000:01:00.0"], "boot_vga": True, "recognized_vendor": True}, {"name": "card1", "pci_address": "0000:03:00.0", "vendor": "NVIDIA", "vendor_id": "0x10de", "device_id": "0x5678", "driver": "nouveau", "iommu_group": "17", "iommu_group_devices": ["0000:03:00.0", "0000:03:00.1"], "boot_vga": False, "recognized_vendor": True}], "usb_devices": [{"id": "1-2", "vendor_id": "1234", "product_id": "5678", "device_class": "00", "driver": "none", "busnum": 1, "devnum": 4, "authorized": True, "host_critical": False}, {"id": "1-1", "vendor_id": "0000", "product_id": "0000", "device_class": "09", "driver": "hub", "busnum": 1, "devnum": 1, "authorized": True, "host_critical": True}]}), encoding="utf-8")
        passthrough = work / "passthrough.json"
        passthrough.write_text(json.dumps({"schema": 1, "assignments": [{"vm": "private-name", "kind": "usb", "devices": ["1-2"], "plan_sha256": "d" * 64}]}), encoding="utf-8")
        storage.write_text(json.dumps({"schema": 1, "generated_unix": 100, "overall": "healthy", "read_only": True, "disks": [{"path": "/dev/sda", "serial": "private-serial", "model": "Bedrock SSD", "size_bytes": 1000000000, "transport": "sata", "smart": {"available": True, "passed": True, "temperature_c": 31, "power_on_hours": 1000, "power_mode": "ACTIVE", "command_exit": 0, "health": "healthy"}}, {"path": "/dev/sdb", "serial": None, "model": "Archive", "size_bytes": 2000000000, "transport": "sas", "smart": {"available": False, "passed": None, "temperature_c": None, "power_on_hours": None, "power_mode": "unknown", "command_exit": 1, "health": "unknown"}}], "software_raid": {"md_arrays": [{"name": "md0", "path": "/dev/md0", "level": "raid1", "state": "active", "member_pattern": "UU", "expected_members": 2, "active_members": 2, "health": "healthy", "sync": {"action": None, "percent": 0}}], "zfs": {"available": True, "pools": [{"name": "main", "size_bytes": 1000, "allocated_bytes": 400, "free_bytes": 600, "health": "ONLINE", "status": "healthy"}]}}, "hardware_raid": {"controllers": [{"address": "0000:01:00.0"}], "management_tools": [], "vendor_reports": [], "explanation": "limited"}}), encoding="utf-8")
        alerts.write_text(json.dumps({"schema": 1, "generated_unix": 101, "attention_required": True, "active_count": 1,
            "active": [{"alert_id": "disk-smart:sda", "kind": "disk-smart", "resource": "/dev/sda", "severity": "critical", "first_seen_unix": 90, "last_seen_unix": 101}]}), encoding="utf-8")
        vms.write_text(json.dumps({"schema": 1, "generated_unix": 102, "domains": [{"name": "private-name", "state": "running", "autostart": True, "vcpus": 4, "memory_mib": 8192, "boot_order": ["disk"], "snapshot_count": 2, "snapshots": ["clean-install", "pre-upgrade"], "image_attachments": ["windows"], "network_attachments": ["private-lan"]}, {"name": "other", "state": "shut off", "autostart": False, "vcpus": 2, "memory_mib": 2048, "boot_order": ["cdrom", "disk"], "snapshot_count": 0, "snapshots": [], "image_attachments": [], "network_attachments": []}]}), encoding="utf-8")
        updates.write_text(json.dumps({"schema": 1, "status": "available", "checked_unix": 103, "installed_generation": 1, "available_generation": 2, "available_version": "0.6.0", "available_channel": "stable"}), encoding="utf-8")
        tasks.write_text(json.dumps({"schema": 1, "generated_unix": 104, "tasks": [{"id": "task-1", "kind": "image-import", "state": "running", "created_unix": 100, "updated_unix": 104, "progress": {"current": 25, "total": 100, "unit": "percent"}}]}), encoding="utf-8")
        audit.write_text(json.dumps({"id": "event-1", "category": "storage", "action": "scrub", "outcome": "succeeded", "occurred_unix": 99}) + "\n", encoding="utf-8")
        remote.write_text(json.dumps({"schema": 2, "devices": [{"id": "42345678-1234-4123-8123-123456789abc", "name": "Office laptop", "created_unix": 1000, "expires_unix": 2000, "revoked": False, "expired": False, "last_seen_unix": None}], "pending_requests": [{"id": "12345678-1234-4123-8123-123456789abc", "approved": False, "expires_in_seconds": 420}]}), encoding="utf-8")
        apps.write_text(json.dumps({"schema": 1, "apps": [{"id": "media", "name": "Media", "network": "bridge", "port_count": 1, "resources": {"cpus": 1, "memory_mib": 512, "pids": 128}, "update_policy": "notify", "created_unix": 100, "running": True, "update_available": True}], "install_candidates": [{"id": "notes", "name": "Notes", "network": "none", "port_count": 0, "resources": {"cpus": 0.5, "memory_mib": 256, "pids": 64}, "update_policy": "manual"}]}), encoding="utf-8")
        backups.write_text(json.dumps({"schema": 1, "plans": [{"id": "daily", "name": "Daily", "kind": "local", "schedule": {"frequency": "daily", "hour_utc": 2, "weekday": None}, "retention": {"daily": 7, "weekly": 4, "monthly": 3}, "created_unix": 100, "last_success_unix": 200, "has_snapshot": True}], "create_candidates": [{"id": "archive", "name": "Archive", "kind": "remote", "schedule": {"frequency": "weekly", "hour_utc": 3, "weekday": 6}, "retention": {"daily": 7, "weekly": 4, "monthly": 12}}]}), encoding="utf-8")
        images.write_text(json.dumps({"schema": 1, "images": [{"name": "installer", "type": "iso", "sha256": "c" * 64, "size_bytes": 4096, "converted": False}]}), encoding="utf-8")
        update_policy.write_text(json.dumps({"schema": 2, "automatic_checks": True, "setup_choice_recorded": True, "channel": "stable"}), encoding="utf-8")
        default_update_policy.write_text(json.dumps({"schema": 2, "automatic_checks": False, "setup_choice_recorded": False, "channel": "stable"}), encoding="utf-8")
        nas.write_text(json.dumps({"schema": 1, "users": [{"name": "alice", "credential_generation": 1, "created_unix": 10, "credential_rotated_unix": 13}], "groups": [{"name": "family", "members": ["alice"], "created_unix": 11}], "datasets": [{"pool": "vault", "name": "private", "path": "/private/path", "acl_subjects": ["family"]}], "shares": [{"name": "private-share"}], "snapshots": [{"name": "private-snapshot"}]}), encoding="utf-8")
        environment = os.environ | {
            "BEDROCK_API_SOCKET": str(socket_path),
            "BEDROCK_API_TOKENS": str(tokens),
            "BEDROCK_API_CAPABILITIES": str(capabilities),
            "BEDROCK_API_HARDWARE": str(hardware), "BEDROCK_API_PASSTHROUGH": str(passthrough), "BEDROCK_API_STORAGE": str(storage),
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
            "BEDROCK_ACTION_BROKER_TASK_WRITER": str(ROOT / "config/includes.chroot/usr/lib/bedrock/record-api-task"),
            "BEDROCK_TEST_CALLS": str(action_calls),
            "BEDROCK_API_TASK_STATE_DIR": str(action_task_state),
            "BEDROCK_ACTION_BROKER_VM_HELPER": str(vm_action_helper),
            "BEDROCK_ACTION_BROKER_VM_REQUESTS": str(vm_action_requests),
            "BEDROCK_VM_ACTION_CALLS": str(vm_action_calls),
            "BEDROCK_ACTION_BROKER_SNAPSHOT_HELPER": str(snapshot_action_helper),
            "BEDROCK_SNAPSHOT_ACTION_CALLS": str(snapshot_action_calls),
            "BEDROCK_ACTION_BROKER_CLONE_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_DELETE_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_RESOURCE_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_CREATE_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_IMAGE_ATTACHMENT_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_IMAGE_CONVERSION_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_BACKUP_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_STORAGE_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_NAS_IDENTITY_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_APP_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_NETWORK_ATTACHMENT_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_PASSTHROUGH_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_REMOTE_DEVICE_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_REMOTE_PAIRING_APPROVAL_HELPER": str(admin_action_helper),
            "BEDROCK_ACTION_BROKER_REMOTE_REQUESTS": str(vm_action_requests),
            "BEDROCK_ACTION_BROKER_BACKUP_REQUESTS": str(vm_action_requests),
            "BEDROCK_ACTION_BROKER_STORAGE_REQUESTS": str(vm_action_requests),
            "BEDROCK_ACTION_BROKER_APP_REQUESTS": str(vm_action_requests),
            "BEDROCK_ACTION_BROKER_VM_DEFINITIONS": str(vm_definitions),
            "BEDROCK_VM_ADMIN_CALLS": str(admin_action_calls),
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
            assert set(schema_body["paths"]) == {"/api/v1/openapi.json", "/api/v1/health", "/api/v1/dashboard", "/api/v1/tasks", "/api/v1/alerts", "/api/v1/audit", "/api/v1/apps", "/api/v1/apps/{id}", "/api/v1/apps/{id}/install", "/api/v1/apps/{id}/power", "/api/v1/apps/{id}/update", "/api/v1/backups", "/api/v1/backups/{id}/create", "/api/v1/backups/{id}/restore-latest", "/api/v1/backups/{id}/run", "/api/v1/groups/{id}/members", "/api/v1/hardware", "/api/v1/images", "/api/v1/images/{name}/convert", "/api/v1/remote/devices", "/api/v1/remote/devices/{id}", "/api/v1/remote/pairings/{id}/approve", "/api/v1/settings", "/api/v1/storage", "/api/v1/storage/{id}/scrub", "/api/v1/users", "/api/v1/virtualization/capabilities", "/api/v1/virtualization/passthrough-candidates", "/api/v1/vms", "/api/v1/vms/{name}", "/api/v1/vms/{name}/clone", "/api/v1/vms/{name}/images", "/api/v1/vms/{name}/networks", "/api/v1/vms/{name}/passthrough", "/api/v1/vms/{name}/power", "/api/v1/vms/{name}/resources", "/api/v1/vms/{name}/snapshots"}
            assert schema_body["security"] == [{"bearerAuth": []}]
            assert set(schema_body["paths"]["/api/v1/settings"]) == {"get", "put"}
            assert set(schema_body["paths"]["/api/v1/users"]) == {"get", "post"}
            concrete = lambda path: path.replace("{name}", "test-vm").replace("{id}", "12345678-1234-4123-8123-123456789abc")
            for documented_path, operations in schema_body["paths"].items():
                for method in operations:
                    body = None if method == "get" else {}
                    headers = None if method == "get" else {"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())}
                    assert request(socket_path, method.upper(), concrete(documented_path), None, body, headers) == (401, {"schema": 1, "error": "unauthorized"})
                    assert request(socket_path, method.upper(), concrete(documented_path), "b" * 64, body, headers) == (401, {"schema": 1, "error": "unauthorized"})
            for documented_path, operations in schema_body["paths"].items():
                response = operations.get("get", {}).get("responses", {}).get("200", {})
                if "content" not in response:
                    continue
                status, value = request(socket_path, "GET", concrete(documented_path))
                assert status == 200, f"documented GET failed: {documented_path}"
                validate_documented_response(schema_body, "get", documented_path, value)
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
            assert remote_body["pending_requests"] == [{"id": "12345678-1234-4123-8123-123456789abc", "approved": False, "expires_in_seconds": 420}]
            assert "public_key" not in json.dumps(remote_body) and "sha256" not in json.dumps(remote_body)
            app_status, app_body = request(socket_path, "GET", "/api/v1/apps")
            assert app_status == 200 and app_body["apps"][0]["id"] == "media" and app_body["apps"][0]["running"] is True and app_body["apps"][0]["update_available"] is True and app_body["install_candidates"][0]["id"] == "notes"
            assert "image" not in json.dumps(app_body) and "digest" not in json.dumps(app_body)
            backup_status, backup_body = request(socket_path, "GET", "/api/v1/backups")
            assert backup_status == 200 and backup_body["plans"][0]["has_snapshot"] is True
            assert "source" not in json.dumps(backup_body) and "repository" not in json.dumps(backup_body) and "last_snapshot" not in json.dumps(backup_body)
            hardware_status, hardware_body = request(socket_path, "GET", "/api/v1/hardware")
            assert hardware_status == 200 and hardware_body["cpu"]["model"] == "Bedrock CPU" and hardware_body["usb_device_count"] == 2
            candidate_status, candidate_body = request(socket_path, "GET", "/api/v1/virtualization/passthrough-candidates")
            assert candidate_status == 200 and candidate_body["gpus"] == [{"id": "0000:03:00.0", "vendor": "NVIDIA", "device_id": "0x5678", "devices": ["0000:03:00.0", "0000:03:00.1"]}]
            assert candidate_body["usb_devices"] == [{"id": "1-2", "vendor_id": "1234", "product_id": "5678"}]
            assert candidate_body["assignments"] == [{"vm": "private-name", "kind": "usb", "devices": ["1-2"]}]
            assert "1-1" not in json.dumps(candidate_body) and "busnum" not in json.dumps(candidate_body) and "plan_sha256" not in json.dumps(candidate_body)
            assert not any(secret in json.dumps(hardware_body) for secret in ["must-not-leak", "/dev/sda", "00:11:22:33:44:55", "0000:01:00.0", "0x1002"])
            vm_status, vm_body = request(socket_path, "GET", "/api/v1/vms")
            assert vm_status == 200 and vm_body["domains"][0]["name"] == "private-name" and vm_body["domains"][0]["snapshot_count"] == 2
            vm_action_id = str(uuid.uuid4())
            vm_action_body = {"schema": 1, "operation": "start", "confirmation": "START VM test-vm"}
            vm_action_headers = {"Content-Type": "application/json", "Idempotency-Key": vm_action_id}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/power", body=vm_action_body, extra_headers=vm_action_headers) == (200, {"schema": 1, "request_id": vm_action_id, "status": "succeeded", "replayed": False})
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/power", body=vm_action_body, extra_headers=vm_action_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/power", body=vm_action_body | {"confirmation": "START VM other"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            assert json.loads(vm_action_calls.read_text(encoding="utf-8")) == {"schema": 1, "name": "test-vm", "action": "start", "confirmation": "START VM test-vm"}
            snapshot_action_id = str(uuid.uuid4())
            snapshot_action_body = {"schema": 1, "snapshot": "clean-install", "operation": "restore", "confirmation": "RESTORE SNAPSHOT clean-install FOR VM test-vm"}
            snapshot_action_headers = {"Content-Type": "application/json", "Idempotency-Key": snapshot_action_id}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/snapshots", body=snapshot_action_body, extra_headers=snapshot_action_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/snapshots", body=snapshot_action_body, extra_headers=snapshot_action_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/snapshots", body=snapshot_action_body | {"confirmation": "RESTORE SNAPSHOT other FOR VM test-vm"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            assert json.loads(snapshot_action_calls.read_text(encoding="utf-8"))["action"] == "restore"
            clone_id = str(uuid.uuid4())
            clone_body = {"schema": 1, "name": "copy-vm", "confirmation": "CLONE VM test-vm AS copy-vm"}
            clone_headers = {"Content-Type": "application/json", "Idempotency-Key": clone_id}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/clone", body=clone_body, extra_headers=clone_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/clone", body=clone_body, extra_headers=clone_headers)[1]["replayed"] is True
            delete_id = str(uuid.uuid4())
            delete_body = {"schema": 1, "confirmation": "DELETE VM test-vm AND STORAGE"}
            delete_headers = {"Content-Type": "application/json", "Idempotency-Key": delete_id}
            assert request(socket_path, "DELETE", "/api/v1/vms/test-vm", body=delete_body, extra_headers=delete_headers)[0] == 200
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[0]["source"] == "test-vm" and admin_requests[0]["name"] == "copy-vm"
            assert admin_requests[1]["action"] == "delete" and len(admin_requests[1]["definition_sha256"]) == 64
            resource_id = str(uuid.uuid4())
            resource_body = {"schema": 1, "vcpus": 6, "memory_mib": 12288, "boot_order": ["cdrom", "disk"], "confirmation": "UPDATE VM test-vm CPU 6 MEMORY 12288 BOOT cdrom,disk"}
            resource_headers = {"Content-Type": "application/json", "Idempotency-Key": resource_id}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/resources", body=resource_body, extra_headers=resource_headers)[0] == 200
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[2]["memory_mib"] == 12288 and admin_requests[2]["boot_order"] == ["cdrom", "disk"]
            create_id = str(uuid.uuid4())
            create_body = {"schema": 1, "name": "new-vm", "vcpus": 4, "memory_mib": 8192, "disk_size_gib": 64, "autostart": False, "confirmation": "CREATE VM new-vm"}
            create_headers = {"Content-Type": "application/json", "Idempotency-Key": create_id}
            assert request(socket_path, "POST", "/api/v1/vms", body=create_body, extra_headers=create_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/vms", body=create_body, extra_headers=create_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/vms", body=create_body | {"confirmation": "CREATE VM other"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            image_attachment_id = str(uuid.uuid4())
            image_attachment_body = {"schema": 1, "image": "installer", "operation": "attach", "confirmation": "ATTACH IMAGE installer TO VM test-vm"}
            image_attachment_headers = {"Content-Type": "application/json", "Idempotency-Key": image_attachment_id}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/images", body=image_attachment_body, extra_headers=image_attachment_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/images", body=image_attachment_body, extra_headers=image_attachment_headers)[1]["replayed"] is True
            network_attachment_id = str(uuid.uuid4())
            network_attachment_body = {"schema": 1, "network": "lab", "operation": "detach", "confirmation": "DETACH NETWORK lab FROM VM test-vm"}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/networks", body=network_attachment_body, extra_headers={"Content-Type": "application/json", "Idempotency-Key": network_attachment_id})[0] == 200
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/networks", body=network_attachment_body | {"confirmation": "DETACH NETWORK other FROM VM test-vm"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            passthrough_id = str(uuid.uuid4())
            passthrough_body = {"schema": 1, "kind": "usb", "devices": ["1-2"], "operation": "assign", "review_confirmation": "REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-2", "confirmation": "ASSIGN USB PASSTHROUGH VM test-vm DEVICES 1-2"}
            passthrough_headers = {"Content-Type": "application/json", "Idempotency-Key": passthrough_id}
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/passthrough", body=passthrough_body, extra_headers=passthrough_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/passthrough", body=passthrough_body, extra_headers=passthrough_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/vms/test-vm/passthrough", body=passthrough_body | {"confirmation": "ASSIGN USB PASSTHROUGH VM wrong DEVICES 1-2"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[3]["name"] == "new-vm" and admin_requests[3]["disk_size_gib"] == 64
            assert admin_requests[4] == {"schema": 1, "vm": "test-vm", "image": "installer", "action": "attach", "confirmation": "ATTACH IMAGE installer TO VM test-vm"}
            assert admin_requests[5] == {"schema": 1, "vm": "test-vm", "network": "lab", "action": "detach", "confirmation": "DETACH NETWORK lab FROM VM test-vm"}
            assert admin_requests[6] == {"schema": 1, "vm": "test-vm", "kind": "usb", "devices": ["1-2"], "action": "assign", "review_confirmation": "REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-2", "confirmation": "ASSIGN USB PASSTHROUGH VM test-vm DEVICES 1-2"}
            remote_device_id = "42345678-1234-4123-8123-123456789abc"
            remote_revoke_id = str(uuid.uuid4())
            remote_revoke_body = {"schema": 1, "operation": "revoke", "confirmation": f"REVOKE REMOTE DEVICE {remote_device_id}"}
            remote_revoke_headers = {"Content-Type": "application/json", "Idempotency-Key": remote_revoke_id}
            assert request(socket_path, "POST", f"/api/v1/remote/devices/{remote_device_id}", body=remote_revoke_body, extra_headers=remote_revoke_headers)[0] == 200
            assert request(socket_path, "POST", f"/api/v1/remote/devices/{remote_device_id}", body=remote_revoke_body, extra_headers=remote_revoke_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", f"/api/v1/remote/devices/{remote_device_id}", body=remote_revoke_body | {"confirmation": "REVOKE REMOTE DEVICE wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[7] == {"schema": 1, "operation": "revoke", "id": remote_device_id, "confirmation": f"REVOKE REMOTE DEVICE {remote_device_id}"}
            pairing_id = "12345678-1234-4123-8123-123456789abc"
            pairing_approval_id = str(uuid.uuid4())
            pairing_body = {"schema": 1, "confirmation": f"APPROVE REMOTE DEVICE {pairing_id}"}
            pairing_headers = {"Content-Type": "application/json", "Idempotency-Key": pairing_approval_id}
            assert request(socket_path, "POST", f"/api/v1/remote/pairings/{pairing_id}/approve", body=pairing_body, extra_headers=pairing_headers)[0] == 200
            assert request(socket_path, "POST", f"/api/v1/remote/pairings/{pairing_id}/approve", body=pairing_body, extra_headers=pairing_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", f"/api/v1/remote/pairings/{pairing_id}/approve", body={"schema": 1, "confirmation": "APPROVE REMOTE DEVICE wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[8] == {"schema": 1, "id": pairing_id, "confirmation": f"APPROVE REMOTE DEVICE {pairing_id}"}
            conversion_id = str(uuid.uuid4())
            source_hash = "c" * 64
            conversion_body = {"schema": 1, "target": "converted", "target_type": "qcow2", "source_sha256": source_hash,
                               "confirmation": f"CONVERT IMAGE installer {source_hash} TO QCOW2 converted"}
            conversion_headers = {"Content-Type": "application/json", "Idempotency-Key": conversion_id}
            assert request(socket_path, "POST", "/api/v1/images/installer/convert", body=conversion_body, extra_headers=conversion_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/images/installer/convert", body=conversion_body, extra_headers=conversion_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/images/installer/convert", body=conversion_body | {"confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[9] == {"schema": 1, "source": "installer", "source_sha256": source_hash, "target": "converted", "target_type": "qcow2", "confirmation": f"CONVERT IMAGE installer {source_hash} TO QCOW2 converted"}
            backup_run_id = str(uuid.uuid4())
            backup_run_body = {"schema": 1, "confirmation": "RUN ENCRYPTED BACKUP nightly"}
            backup_run_headers = {"Content-Type": "application/json", "Idempotency-Key": backup_run_id}
            assert request(socket_path, "POST", "/api/v1/backups/nightly/run", body=backup_run_body, extra_headers=backup_run_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/backups/nightly/run", body=backup_run_body, extra_headers=backup_run_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/backups/nightly/run", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[10] == {"schema": 1, "id": "nightly", "operation": "run", "confirmation": "RUN ENCRYPTED BACKUP nightly"}
            backup_restore_id = str(uuid.uuid4())
            backup_restore_body = {"schema": 1, "confirmation": "RESTORE LATEST BACKUP nightly"}
            backup_restore_headers = {"Content-Type": "application/json", "Idempotency-Key": backup_restore_id}
            assert request(socket_path, "POST", "/api/v1/backups/nightly/restore-latest", body=backup_restore_body, extra_headers=backup_restore_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/backups/nightly/restore-latest", body=backup_restore_body, extra_headers=backup_restore_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/backups/nightly/restore-latest", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[11] == {"schema": 1, "id": "nightly", "operation": "restore-latest", "confirmation": "RESTORE LATEST BACKUP nightly"}
            backup_create_id = str(uuid.uuid4())
            backup_create_body = {"schema": 1, "confirmation": "CREATE ENCRYPTED BACKUP archive"}
            backup_create_headers = {"Content-Type": "application/json", "Idempotency-Key": backup_create_id}
            assert request(socket_path, "POST", "/api/v1/backups/archive/create", body=backup_create_body, extra_headers=backup_create_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/backups/archive/create", body=backup_create_body, extra_headers=backup_create_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/backups/archive/create", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[12] == {"schema": 1, "id": "archive", "operation": "create-staged", "confirmation": "CREATE ENCRYPTED BACKUP archive"}
            storage_scrub_id = str(uuid.uuid4())
            storage_scrub_body = {"schema": 1, "confirmation": "SCRUB STORAGE main"}
            storage_scrub_headers = {"Content-Type": "application/json", "Idempotency-Key": storage_scrub_id}
            assert request(socket_path, "POST", "/api/v1/storage/main/scrub", body=storage_scrub_body, extra_headers=storage_scrub_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/storage/main/scrub", body=storage_scrub_body, extra_headers=storage_scrub_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/storage/main/scrub", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[13] == {"schema": 1, "id": "main", "operation": "scrub", "confirmation": "SCRUB STORAGE main"}
            nas_identity_id = str(uuid.uuid4())
            nas_identity_body = {"schema": 1, "kind": "user", "name": "bob", "confirmation": "CREATE NAS USER bob"}
            nas_identity_headers = {"Content-Type": "application/json", "Idempotency-Key": nas_identity_id}
            assert request(socket_path, "POST", "/api/v1/users", body=nas_identity_body, extra_headers=nas_identity_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/users", body=nas_identity_body, extra_headers=nas_identity_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/users", body=nas_identity_body | {"confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[14] == {"schema": 1, "id": "bob", "operation": "create-user", "confirmation": "CREATE NAS USER bob"}
            membership_id = str(uuid.uuid4())
            membership_body = {"schema": 1, "user": "alice", "confirmation": "ADD NAS USER alice TO GROUP family"}
            membership_headers = {"Content-Type": "application/json", "Idempotency-Key": membership_id}
            assert request(socket_path, "POST", "/api/v1/groups/family/members", body=membership_body, extra_headers=membership_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/groups/family/members", body=membership_body, extra_headers=membership_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/groups/family/members", body=membership_body | {"confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[15] == {"schema": 1, "id": "family", "subject": "alice", "operation": "add-member", "confirmation": "ADD NAS USER alice TO GROUP family"}
            app_control_id = str(uuid.uuid4())
            app_control_body = {"schema": 1, "operation": "stop", "confirmation": "STOP APPLICATION media"}
            app_control_headers = {"Content-Type": "application/json", "Idempotency-Key": app_control_id}
            assert request(socket_path, "POST", "/api/v1/apps/media/power", body=app_control_body, extra_headers=app_control_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/apps/media/power", body=app_control_body, extra_headers=app_control_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/apps/media/power", body=app_control_body | {"confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[16] == {"schema": 1, "id": "media", "operation": "stop", "confirmation": "STOP APPLICATION media"}
            app_remove_id = str(uuid.uuid4())
            app_remove_body = {"schema": 1, "confirmation": "REMOVE APPLICATION media"}
            app_remove_headers = {"Content-Type": "application/json", "Idempotency-Key": app_remove_id}
            assert request(socket_path, "DELETE", "/api/v1/apps/media", body=app_remove_body, extra_headers=app_remove_headers)[0] == 200
            assert request(socket_path, "DELETE", "/api/v1/apps/media", body=app_remove_body, extra_headers=app_remove_headers)[1]["replayed"] is True
            assert request(socket_path, "DELETE", "/api/v1/apps/media", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[17] == {"schema": 1, "id": "media", "operation": "remove", "confirmation": "REMOVE APPLICATION media"}
            app_update_id = str(uuid.uuid4())
            app_update_body = {"schema": 1, "confirmation": "UPDATE APPLICATION media"}
            app_update_headers = {"Content-Type": "application/json", "Idempotency-Key": app_update_id}
            assert request(socket_path, "POST", "/api/v1/apps/media/update", body=app_update_body, extra_headers=app_update_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/apps/media/update", body=app_update_body, extra_headers=app_update_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/apps/media/update", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[18] == {"schema": 1, "id": "media", "operation": "update-latest", "confirmation": "UPDATE APPLICATION media"}
            app_install_id = str(uuid.uuid4())
            app_install_body = {"schema": 1, "confirmation": "INSTALL APPLICATION notes"}
            app_install_headers = {"Content-Type": "application/json", "Idempotency-Key": app_install_id}
            assert request(socket_path, "POST", "/api/v1/apps/notes/install", body=app_install_body, extra_headers=app_install_headers)[0] == 200
            assert request(socket_path, "POST", "/api/v1/apps/notes/install", body=app_install_body, extra_headers=app_install_headers)[1]["replayed"] is True
            assert request(socket_path, "POST", "/api/v1/apps/notes/install", body={"schema": 1, "confirmation": "wrong"}, extra_headers={"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())})[0] == 400
            admin_requests = [json.loads(line) for line in admin_action_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[19] == {"schema": 1, "id": "notes", "operation": "install-staged", "confirmation": "INSTALL APPLICATION notes"}
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
            backups.write_text('{"schema":1,"plans":[],"create_candidates":[{"id":"Bad ID"}]}', encoding="utf-8")
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
