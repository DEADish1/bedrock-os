#!/usr/bin/python3
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


def main():
    if not hasattr(socket, "SO_PEERCRED"):
        raise SystemExit("SO_PEERCRED support is required")
    with tempfile.TemporaryDirectory(prefix="bedrock-action-broker-") as temporary:
        work = pathlib.Path(temporary)
        socket_path, state, calls = work / "action.sock", work / "results.json", work / "calls"
        helper = work / "helper"
        helper.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$BEDROCK_TEST_CALLS\"\n", encoding="utf-8")
        helper.chmod(0o755)
        environment = os.environ | {
            "BEDROCK_ACTION_BROKER_TEST_MODE": "1", "BEDROCK_ACTION_BROKER_EXPECTED_UID": str(os.getuid()),
            "BEDROCK_ACTION_BROKER_SOCKET": str(socket_path), "BEDROCK_ACTION_BROKER_STATE": str(state),
            "BEDROCK_ACTION_BROKER_UPDATE_HELPER": str(helper), "BEDROCK_TEST_CALLS": str(calls),
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
            assert calls.read_text(encoding="utf-8").splitlines() == [
                "channel stable", "channel beta I_ACCEPT_PRERELEASE_UPDATE_RISK", "automatic-checks off"
            ]

            invalid_id = str(uuid.uuid4())
            assert exchange(socket_path, request(invalid_id, value="beta"))["error"]["code"] == "invalid-update-policy"
            extra = request(str(uuid.uuid4())) | {"command": "id"}
            assert exchange(socket_path, extra)["error"]["code"] == "invalid-request"
            assert exchange(socket_path, b"not-json")["error"]["code"] == "invalid-json"
            assert exchange(socket_path, b"{" + b" " * 16384)["error"]["code"] == "request-too-large"
            assert len(calls.read_text(encoding="utf-8").splitlines()) == 3

            ledger = json.loads(state.read_text(encoding="utf-8"))
            assert ledger["schema"] == 1 and len(ledger["results"]) == 3
            serialized = state.read_text(encoding="utf-8")
            assert "I_ACCEPT" not in serialized and "automatic_checks" not in serialized
            assert state.stat().st_mode & 0o777 == 0o600
        finally:
            process.terminate()
            process.wait(timeout=2)
    print("action broker tests passed")


if __name__ == "__main__":
    main()
