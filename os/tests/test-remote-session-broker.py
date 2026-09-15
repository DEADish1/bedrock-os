#!/usr/bin/python3
import array
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BROKER = ROOT / "os/config/includes.chroot/usr/lib/bedrock/bedrock-remote-session-broker"
DEVICE = "42345678-1234-4123-8123-123456789abc"
SESSION = "52345678-1234-4123-8123-123456789abc"


def control(path: pathlib.Path, value: dict, descriptors: list[int]) -> dict:
    rights = array.array("i", descriptors)
    with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as client:
        client.connect(str(path))
        client.sendmsg([json.dumps(value, separators=(",", ":")).encode("ascii")],
                       [(socket.SOL_SOCKET, socket.SCM_RIGHTS, rights)])
        return json.loads(client.recv(1024))


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        work = pathlib.Path(temporary)
        helper = work / "helper"
        helper.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$BEDROCK_TEST_BROKER_LOG\"\nIFS= read -r line\nprintf 'echo:%s\\n' \"$line\"\n", encoding="utf-8")
        helper.chmod(0o755)
        broker_socket = work / "broker.sock"
        log = work / "log"
        environment = os.environ | {
            "BEDROCK_REMOTE_BROKER_TEST_MODE": "1",
            "BEDROCK_REMOTE_BROKER_SOCKET": str(broker_socket),
            "BEDROCK_REMOTE_BROKER_EXPECTED_UID": str(os.getuid()),
            "BEDROCK_REMOTE_BROKER_DEVICE_HELPER": str(helper),
            "BEDROCK_REMOTE_BROKER_PAIRING_HELPER": str(helper),
            "BEDROCK_TEST_BROKER_LOG": str(log),
        }
        broker = subprocess.Popen([str(BROKER)], env=environment)
        try:
            for _ in range(100):
                if broker_socket.exists():
                    break
                if broker.poll() is not None:
                    raise AssertionError("session broker exited")
                time.sleep(0.02)
            left, right = socket.socketpair()
            try:
                accepted = control(broker_socket, {"schema": 1, "mode": "device", "device_id": DEVICE,
                                                   "session_id": SESSION}, [left.fileno()])
                assert accepted == {"schema": 1, "status": "accepted"}
                right.sendall(b"opaque-noise-bytes\n")
                assert right.recv(1024) == b"echo:opaque-noise-bytes\n"
            finally:
                left.close(); right.close()
            for _ in range(100):
                if log.exists():
                    break
                time.sleep(0.01)
            assert log.read_text(encoding="utf-8").strip() == f"{DEVICE} {SESSION}"
            assert control(broker_socket, {"schema": 1, "mode": "pairing", "session_id": SESSION}, []) == {
                "schema": 1, "status": "rejected"}
            bad_left, bad_right = socket.socketpair()
            try:
                assert control(broker_socket, {"schema": 1, "mode": "device", "device_id": "../bad",
                                               "session_id": SESSION}, [bad_left.fileno()]) == {
                    "schema": 1, "status": "rejected"}
            finally:
                bad_left.close(); bad_right.close()
        finally:
            broker.terminate(); broker.wait(timeout=3)
    print("Remote connected-stream broker tests passed.")


if __name__ == "__main__":
    main()
