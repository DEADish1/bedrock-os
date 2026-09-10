#!/usr/bin/python3
import hashlib
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
BROKER = ROOT / "config/includes.chroot/usr/lib/bedrock/bedrock-action-broker"
TASK_WRITER = ROOT / "config/includes.chroot/usr/lib/bedrock/record-api-task"


def exchange(path, value):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(2)
    client.connect(str(path))
    raw = value if isinstance(value, bytes) else json.dumps(value).encode()
    client.sendall(raw)
    client.shutdown(socket.SHUT_WR)
    response = json.loads(client.recv(65536))
    client.close()
    return response


def request(request_id, setting="channel", value="stable", acknowledged=False):
    return {"schema": 1, "request_id": request_id, "action": "update-policy", "setting": setting,
            "value": value, "beta_risk_acknowledged": acknowledged}


def vm_request(request_id, operation="start", confirmation="START VM test-vm"):
    return {"schema": 1, "request_id": request_id, "action": "vm-control", "name": "test-vm",
            "operation": operation, "confirmation": confirmation}


def snapshot_request(request_id, operation="create", confirmation="CREATE SNAPSHOT clean-install FOR VM test-vm"):
    return {"schema": 1, "request_id": request_id, "action": "vm-snapshot", "name": "test-vm",
            "snapshot": "clean-install", "operation": operation, "confirmation": confirmation}


def clone_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "vm-clone", "source": "test-vm",
            "name": "copy-vm", "confirmation": "CLONE VM test-vm AS copy-vm"}


def delete_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "vm-delete", "name": "test-vm",
            "confirmation": "DELETE VM test-vm AND STORAGE"}


def resource_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "vm-resources", "name": "test-vm",
            "vcpus": 6, "memory_mib": 12288, "boot_order": ["cdrom", "disk"],
            "confirmation": "UPDATE VM test-vm CPU 6 MEMORY 12288 BOOT cdrom,disk"}


def create_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "vm-create", "name": "new-vm",
            "vcpus": 4, "memory_mib": 8192, "disk_size_gib": 64, "autostart": False,
            "confirmation": "CREATE VM new-vm"}


def attachment_request(request_id, kind="image", operation="attach"):
    item = "installer" if kind == "image" else "lab"
    label = kind.upper()
    confirmation = f"ATTACH {label} {item} TO VM test-vm" if operation == "attach" else f"DETACH {label} {item} FROM VM test-vm"
    return {"schema": 1, "request_id": request_id, "action": f"vm-{kind}-attachment", "name": "test-vm",
            kind: item, "operation": operation, "confirmation": confirmation}


def passthrough_request(request_id, operation="assign"):
    devices = ["1-2"]
    return {"schema": 1, "request_id": request_id, "action": "vm-passthrough", "name": "test-vm",
            "kind": "usb", "devices": devices, "operation": operation,
            "review_confirmation": "REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-2",
            "confirmation": f"{operation.upper()} USB PASSTHROUGH VM test-vm DEVICES 1-2"}


def remote_device_request(request_id, operation="revoke"):
    device_id = "42345678-1234-4123-8123-123456789abc"
    return {"schema": 1, "request_id": request_id, "action": "remote-device", "operation": operation, "id": device_id,
            "confirmation": f"REVOKE REMOTE DEVICE {device_id}"}


def pairing_approval_request(request_id):
    pairing_id = "12345678-1234-4123-8123-123456789abc"
    return {"schema": 1, "request_id": request_id, "action": "remote-pairing-approve", "id": pairing_id,
            "confirmation": f"APPROVE REMOTE DEVICE {pairing_id}"}


def image_conversion_request(request_id):
    source_hash = "c" * 64
    return {"schema": 1, "request_id": request_id, "action": "image-convert", "source": "source",
            "source_sha256": source_hash, "target": "converted", "target_type": "qcow2",
            "confirmation": f"CONVERT IMAGE source {source_hash} TO QCOW2 converted"}


def backup_run_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "backup-run", "id": "nightly",
            "confirmation": "RUN ENCRYPTED BACKUP nightly"}

def backup_restore_latest_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "backup-restore-latest", "id": "nightly",
            "confirmation": "RESTORE LATEST BACKUP nightly"}

def backup_create_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "backup-create", "id": "archive",
            "confirmation": "CREATE ENCRYPTED BACKUP archive"}

def storage_scrub_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "storage-scrub", "id": "vault",
            "confirmation": "SCRUB STORAGE vault"}

def nas_identity_request(request_id, kind="user"):
    identity = "alice" if kind == "user" else "family"
    return {"schema": 1, "request_id": request_id, "action": "nas-identity-create", "id": identity,
            "operation": f"create-{kind}", "confirmation": f"CREATE NAS {kind.upper()} {identity}"}

def nas_membership_request(request_id):
    return {"schema": 1, "request_id": request_id, "action": "nas-membership-add", "id": "family",
            "subject": "alice", "confirmation": "ADD NAS USER alice TO GROUP family"}

def app_control_request(request_id, operation="stop"):
    return {"schema": 1, "request_id": request_id, "action": "app-control", "id": "photos", "operation": operation,
            "confirmation": f"{operation.upper()} APPLICATION photos"}


def main():
    if not hasattr(socket, "SO_PEERCRED"):
        raise SystemExit("SO_PEERCRED support is required")
    with tempfile.TemporaryDirectory(prefix="bedrock-action-broker-") as temporary:
        work = pathlib.Path(temporary)
        socket_path, state, calls = work / "action.sock", work / "results.json", work / "calls"
        task_state = work / "task-state"
        vm_requests, vm_calls = work / "vm-requests", work / "vm-calls"
        snapshot_calls = work / "snapshot-calls"
        admin_calls, definitions = work / "admin-calls", work / "definitions"
        definitions.mkdir()
        (definitions / "test-vm.xml").write_text("<domain/>\n", encoding="utf-8")
        helper = work / "helper"
        helper.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$BEDROCK_TEST_CALLS\"\n[ \"$*\" != 'automatic-checks on' ]\n", encoding="utf-8")
        helper.chmod(0o755)
        vm_helper = work / "vm-helper"
        vm_helper.write_text("#!/bin/sh\ncat \"$1\" >> \"$BEDROCK_TEST_CALLS\"\n", encoding="utf-8")
        vm_helper.chmod(0o755)
        snapshot_helper = work / "snapshot-helper"
        snapshot_helper.write_text("#!/bin/sh\ncat \"$1\" >> \"$BEDROCK_SNAPSHOT_ACTION_CALLS\"\n", encoding="utf-8")
        snapshot_helper.chmod(0o755)
        admin_helper = work / "admin-helper"
        admin_helper.write_text("#!/bin/sh\ncat \"$1\" >> \"$BEDROCK_VM_ADMIN_CALLS\"\n", encoding="utf-8")
        admin_helper.chmod(0o755)
        environment = os.environ | {
            "BEDROCK_ACTION_BROKER_TEST_MODE": "1", "BEDROCK_ACTION_BROKER_EXPECTED_UID": str(os.getuid()),
            "BEDROCK_ACTION_BROKER_SOCKET": str(socket_path), "BEDROCK_ACTION_BROKER_STATE": str(state),
            "BEDROCK_ACTION_BROKER_UPDATE_HELPER": str(helper), "BEDROCK_TEST_CALLS": str(calls),
            "BEDROCK_ACTION_BROKER_TASK_WRITER": str(TASK_WRITER),
            "BEDROCK_API_TASK_STATE_DIR": str(task_state),
            "BEDROCK_ACTION_BROKER_VM_HELPER": str(vm_helper),
            "BEDROCK_ACTION_BROKER_VM_REQUESTS": str(vm_requests),
            "BEDROCK_ACTION_BROKER_SNAPSHOT_HELPER": str(snapshot_helper),
            "BEDROCK_SNAPSHOT_ACTION_CALLS": str(snapshot_calls),
            "BEDROCK_ACTION_BROKER_CLONE_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_DELETE_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_RESOURCE_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_CREATE_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_IMAGE_ATTACHMENT_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_NETWORK_ATTACHMENT_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_PASSTHROUGH_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_IMAGE_CONVERSION_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_BACKUP_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_STORAGE_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_NAS_IDENTITY_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_APP_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_REMOTE_DEVICE_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_REMOTE_PAIRING_APPROVAL_HELPER": str(admin_helper),
            "BEDROCK_ACTION_BROKER_REMOTE_REQUESTS": str(vm_requests),
            "BEDROCK_ACTION_BROKER_BACKUP_REQUESTS": str(vm_requests),
            "BEDROCK_ACTION_BROKER_STORAGE_REQUESTS": str(vm_requests),
            "BEDROCK_ACTION_BROKER_APP_REQUESTS": str(vm_requests),
            "BEDROCK_ACTION_BROKER_VM_DEFINITIONS": str(definitions),
            "BEDROCK_VM_ADMIN_CALLS": str(admin_calls),
        }
        process = subprocess.Popen([sys.executable, str(BROKER)], env=environment)
        try:
            for _ in range(50):
                if socket_path.exists():
                    break
                time.sleep(0.05)
            else:
                raise AssertionError("broker socket did not appear")

            stable_id = str(uuid.uuid4())
            assert exchange(socket_path, request(stable_id)) == {"schema": 1, "request_id": stable_id, "status": "succeeded", "replayed": False}
            assert exchange(socket_path, request(stable_id))["replayed"] is True
            assert exchange(socket_path, request(stable_id, value="beta", acknowledged=True))["error"]["code"] == "idempotency-conflict"
            beta_id = str(uuid.uuid4())
            assert exchange(socket_path, request(beta_id, value="beta", acknowledged=True))["status"] == "succeeded"
            checks_id = str(uuid.uuid4())
            assert exchange(socket_path, request(checks_id, "automatic_checks", False))["status"] == "succeeded"
            failed_id = str(uuid.uuid4())
            assert exchange(socket_path, request(failed_id, "automatic_checks", True))["error"]["code"] == "action-failed"
            assert exchange(socket_path, request(failed_id, "automatic_checks", True))["error"]["code"] == "action-failed"
            assert calls.read_text(encoding="utf-8").splitlines() == [
                "channel stable", "channel beta I_ACCEPT_PRERELEASE_UPDATE_RISK", "automatic-checks off", "automatic-checks on"
            ]

            invalid_id = str(uuid.uuid4())
            assert exchange(socket_path, request(invalid_id, value="beta"))["error"]["code"] == "invalid-update-policy"
            extra = request(str(uuid.uuid4())) | {"command": "id"}
            assert exchange(socket_path, extra)["error"]["code"] == "invalid-request"
            assert exchange(socket_path, b"not-json")["error"]["code"] == "invalid-json"
            assert exchange(socket_path, b"{" + b" " * 16384)["error"]["code"] == "request-too-large"
            assert len(calls.read_text(encoding="utf-8").splitlines()) == 4

            environment["BEDROCK_TEST_CALLS"] = str(vm_calls)
            process.terminate()
            process.wait(timeout=2)
            socket_path.unlink(missing_ok=True)
            process = subprocess.Popen([sys.executable, str(BROKER)], env=environment)
            for _ in range(50):
                if socket_path.exists():
                    break
                time.sleep(0.05)
            vm_id = str(uuid.uuid4())
            assert exchange(socket_path, vm_request(vm_id))["status"] == "succeeded"
            assert exchange(socket_path, vm_request(vm_id))["replayed"] is True
            assert exchange(socket_path, vm_request(vm_id, "stop", "STOP VM test-vm"))["error"]["code"] == "idempotency-conflict"
            assert exchange(socket_path, vm_request(str(uuid.uuid4()), "start", "START VM other"))["error"]["code"] == "invalid-vm-control"
            assert json.loads(vm_calls.read_text(encoding="utf-8")) == {"schema": 1, "name": "test-vm", "action": "start", "confirmation": "START VM test-vm"}
            assert not any(vm_requests.iterdir())
            snapshot_id = str(uuid.uuid4())
            assert exchange(socket_path, snapshot_request(snapshot_id))["status"] == "succeeded"
            assert exchange(socket_path, snapshot_request(snapshot_id))["replayed"] is True
            assert exchange(socket_path, snapshot_request(str(uuid.uuid4()), confirmation="CREATE SNAPSHOT wrong FOR VM test-vm"))["error"]["code"] == "invalid-vm-snapshot"
            assert json.loads(snapshot_calls.read_text(encoding="utf-8")) == {"schema": 1, "name": "test-vm", "snapshot": "clean-install", "action": "create", "confirmation": "CREATE SNAPSHOT clean-install FOR VM test-vm"}
            assert not any(vm_requests.iterdir())
            clone_id = str(uuid.uuid4())
            assert exchange(socket_path, clone_request(clone_id))["status"] == "succeeded"
            assert exchange(socket_path, clone_request(clone_id))["replayed"] is True
            assert exchange(socket_path, clone_request(str(uuid.uuid4())) | {"confirmation": "CLONE VM other AS copy-vm"})["error"]["code"] == "invalid-vm-clone"
            delete_id = str(uuid.uuid4())
            assert exchange(socket_path, delete_request(delete_id))["status"] == "succeeded"
            assert exchange(socket_path, delete_request(delete_id))["replayed"] is True
            admin_requests = [json.loads(line) for line in admin_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[0] == {"schema": 1, "source": "test-vm", "name": "copy-vm", "confirmation": "CLONE VM test-vm AS copy-vm"}
            assert admin_requests[1]["action"] == "delete" and admin_requests[1]["definition_sha256"] == hashlib.sha256(b"<domain/>\n").hexdigest()
            resource_id = str(uuid.uuid4())
            assert exchange(socket_path, resource_request(resource_id))["status"] == "succeeded"
            assert exchange(socket_path, resource_request(resource_id))["replayed"] is True
            admin_requests = [json.loads(line) for line in admin_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[2]["vcpus"] == 6 and admin_requests[2]["boot_order"] == ["cdrom", "disk"]
            create_id = str(uuid.uuid4())
            assert exchange(socket_path, create_request(create_id))["status"] == "succeeded"
            assert exchange(socket_path, create_request(create_id))["replayed"] is True
            assert exchange(socket_path, create_request(str(uuid.uuid4())) | {"confirmation": "CREATE VM other"})["error"]["code"] == "invalid-vm-create"
            image_id = str(uuid.uuid4())
            assert exchange(socket_path, attachment_request(image_id))["status"] == "succeeded"
            assert exchange(socket_path, attachment_request(image_id))["replayed"] is True
            assert exchange(socket_path, attachment_request(str(uuid.uuid4())) | {"confirmation": "ATTACH IMAGE wrong TO VM test-vm"})["error"]["code"] == "invalid-vm-image-attachment"
            network_id = str(uuid.uuid4())
            assert exchange(socket_path, attachment_request(network_id, "network", "detach"))["status"] == "succeeded"
            passthrough_id = str(uuid.uuid4())
            assert exchange(socket_path, passthrough_request(passthrough_id))["status"] == "succeeded"
            assert exchange(socket_path, passthrough_request(passthrough_id))["replayed"] is True
            assert exchange(socket_path, passthrough_request(str(uuid.uuid4())) | {"confirmation": "ASSIGN USB PASSTHROUGH VM wrong DEVICES 1-2"})["error"]["code"] == "invalid-vm-passthrough"
            remote_id = str(uuid.uuid4())
            assert exchange(socket_path, remote_device_request(remote_id))["status"] == "succeeded"
            assert exchange(socket_path, remote_device_request(remote_id))["replayed"] is True
            assert exchange(socket_path, remote_device_request(str(uuid.uuid4())) | {"confirmation": "REVOKE REMOTE DEVICE wrong"})["error"]["code"] == "invalid-remote-device"
            approval_id = str(uuid.uuid4())
            assert exchange(socket_path, pairing_approval_request(approval_id))["status"] == "succeeded"
            assert exchange(socket_path, pairing_approval_request(approval_id))["replayed"] is True
            assert exchange(socket_path, pairing_approval_request(str(uuid.uuid4())) | {"confirmation": "APPROVE REMOTE DEVICE wrong"})["error"]["code"] == "invalid-remote-pairing-approval"
            conversion_id = str(uuid.uuid4())
            assert exchange(socket_path, image_conversion_request(conversion_id))["status"] == "succeeded"
            assert exchange(socket_path, image_conversion_request(conversion_id))["replayed"] is True
            assert exchange(socket_path, image_conversion_request(str(uuid.uuid4())) | {"target": "source"})["error"]["code"] == "invalid-image-conversion"
            backup_id = str(uuid.uuid4())
            assert exchange(socket_path, backup_run_request(backup_id))["status"] == "succeeded"
            assert exchange(socket_path, backup_run_request(backup_id))["replayed"] is True
            assert exchange(socket_path, backup_run_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-backup-run"
            restore_id = str(uuid.uuid4())
            assert exchange(socket_path, backup_restore_latest_request(restore_id))["status"] == "succeeded"
            assert exchange(socket_path, backup_restore_latest_request(restore_id))["replayed"] is True
            assert exchange(socket_path, backup_restore_latest_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-backup-restore-latest"
            create_backup_id = str(uuid.uuid4())
            assert exchange(socket_path, backup_create_request(create_backup_id))["status"] == "succeeded"
            assert exchange(socket_path, backup_create_request(create_backup_id))["replayed"] is True
            assert exchange(socket_path, backup_create_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-backup-create"
            scrub_id = str(uuid.uuid4())
            assert exchange(socket_path, storage_scrub_request(scrub_id))["status"] == "succeeded"
            assert exchange(socket_path, storage_scrub_request(scrub_id))["replayed"] is True
            assert exchange(socket_path, storage_scrub_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-storage-scrub"
            nas_id = str(uuid.uuid4())
            assert exchange(socket_path, nas_identity_request(nas_id))["status"] == "succeeded"
            assert exchange(socket_path, nas_identity_request(nas_id))["replayed"] is True
            assert exchange(socket_path, nas_identity_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-nas-identity-create"
            membership_id = str(uuid.uuid4())
            assert exchange(socket_path, nas_membership_request(membership_id))["status"] == "succeeded"
            assert exchange(socket_path, nas_membership_request(membership_id))["replayed"] is True
            assert exchange(socket_path, nas_membership_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-nas-membership-add"
            app_id = str(uuid.uuid4())
            assert exchange(socket_path, app_control_request(app_id))["status"] == "succeeded"
            assert exchange(socket_path, app_control_request(app_id))["replayed"] is True
            app_remove_id = str(uuid.uuid4())
            assert exchange(socket_path, app_control_request(app_remove_id, "remove"))["status"] == "succeeded"
            app_update_id = str(uuid.uuid4())
            update_request = app_control_request(app_update_id, "update-latest") | {"confirmation": "UPDATE APPLICATION photos"}
            assert exchange(socket_path, update_request)["status"] == "succeeded"
            app_install_id = str(uuid.uuid4())
            install_request = app_control_request(app_install_id, "install-staged") | {"confirmation": "INSTALL APPLICATION photos"}
            assert exchange(socket_path, install_request)["status"] == "succeeded"
            assert exchange(socket_path, app_control_request(str(uuid.uuid4())) | {"confirmation": "wrong"})["error"]["code"] == "invalid-app-control"
            admin_requests = [json.loads(line) for line in admin_calls.read_text(encoding="utf-8").splitlines()]
            assert admin_requests[3]["name"] == "new-vm" and admin_requests[3]["disk_size_gib"] == 64
            assert admin_requests[4] == {"schema": 1, "vm": "test-vm", "image": "installer", "action": "attach", "confirmation": "ATTACH IMAGE installer TO VM test-vm"}
            assert admin_requests[5] == {"schema": 1, "vm": "test-vm", "network": "lab", "action": "detach", "confirmation": "DETACH NETWORK lab FROM VM test-vm"}
            assert admin_requests[6] == {"schema": 1, "vm": "test-vm", "kind": "usb", "devices": ["1-2"], "action": "assign", "review_confirmation": "REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-2", "confirmation": "ASSIGN USB PASSTHROUGH VM test-vm DEVICES 1-2"}
            assert admin_requests[7] == {"schema": 1, "operation": "revoke", "id": "42345678-1234-4123-8123-123456789abc", "confirmation": "REVOKE REMOTE DEVICE 42345678-1234-4123-8123-123456789abc"}
            assert admin_requests[8] == {"schema": 1, "id": "12345678-1234-4123-8123-123456789abc", "confirmation": "APPROVE REMOTE DEVICE 12345678-1234-4123-8123-123456789abc"}
            assert admin_requests[9] == {"schema": 1, "source": "source", "source_sha256": "c" * 64, "target": "converted", "target_type": "qcow2", "confirmation": f"CONVERT IMAGE source {'c' * 64} TO QCOW2 converted"}
            assert admin_requests[10] == {"schema": 1, "id": "nightly", "operation": "run", "confirmation": "RUN ENCRYPTED BACKUP nightly"}
            assert admin_requests[11] == {"schema": 1, "id": "nightly", "operation": "restore-latest", "confirmation": "RESTORE LATEST BACKUP nightly"}
            assert admin_requests[12] == {"schema": 1, "id": "archive", "operation": "create-staged", "confirmation": "CREATE ENCRYPTED BACKUP archive"}
            assert admin_requests[13] == {"schema": 1, "id": "vault", "operation": "scrub", "confirmation": "SCRUB STORAGE vault"}
            assert admin_requests[14] == {"schema": 1, "id": "alice", "operation": "create-user", "confirmation": "CREATE NAS USER alice"}
            assert admin_requests[15] == {"schema": 1, "id": "family", "subject": "alice", "operation": "add-member", "confirmation": "ADD NAS USER alice TO GROUP family"}
            assert admin_requests[16] == {"schema": 1, "id": "photos", "operation": "stop", "confirmation": "STOP APPLICATION photos"}
            assert admin_requests[17] == {"schema": 1, "id": "photos", "operation": "remove", "confirmation": "REMOVE APPLICATION photos"}
            assert admin_requests[18] == {"schema": 1, "id": "photos", "operation": "update-latest", "confirmation": "UPDATE APPLICATION photos"}
            assert admin_requests[19] == {"schema": 1, "id": "photos", "operation": "install-staged", "confirmation": "INSTALL APPLICATION photos"}
            assert not any(vm_requests.iterdir())

            ledger = json.loads(state.read_text(encoding="utf-8"))
            assert ledger["schema"] == 1 and len(ledger["results"]) == 26
            serialized = state.read_text(encoding="utf-8")
            assert "I_ACCEPT" not in serialized and "automatic_checks" not in serialized
            assert state.stat().st_mode & 0o777 == 0o600
            tasks = json.loads((task_state / "tasks.json").read_text(encoding="utf-8"))
            assert len(tasks["tasks"]) == 4 and sum(item["state"] == "succeeded" for item in tasks["tasks"]) == 3 and sum(item["state"] == "failed" for item in tasks["tasks"]) == 1
            assert all(item["kind"] == "update-policy" for item in tasks["tasks"])
            audit = (task_state / "audit.jsonl").read_text(encoding="utf-8").splitlines()
            assert len(audit) == 4 and all(json.loads(line)["action"] == "update-policy" for line in audit)
            assert sum(json.loads(line)["outcome"] == "failed" for line in audit) == 1
        finally:
            process.terminate()
            process.wait(timeout=2)
    print("action broker tests passed")


if __name__ == "__main__":
    main()
