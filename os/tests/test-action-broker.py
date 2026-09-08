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
            assert not any(vm_requests.iterdir())

            ledger = json.loads(state.read_text(encoding="utf-8"))
            assert ledger["schema"] == 1 and len(ledger["results"]) == 8
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
