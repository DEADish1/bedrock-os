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

ROOT = pathlib.Path(__file__).resolve().parents[2]
GATEWAY = ROOT / "os/config/includes.chroot/usr/lib/bedrock/bedrock-pairing-gateway"
MANAGER = ROOT / "os/config/includes.chroot/usr/lib/bedrock/manage-remote-pairing"
PAIRING_ID = "12345678-1234-4123-8123-123456789abc"
DEVICE_ID = "42345678-1234-4123-8123-123456789abc"
BOOT_ID = "87654321-4321-4321-8321-cba987654321"
CODE = "BRK-ABCD-2345"

def exchange(path: pathlib.Path, value: object | bytes) -> dict:
    raw = value if isinstance(value, bytes) else json.dumps(value, separators=(",", ":")).encode("ascii")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3)
        client.connect(str(path))
        client.sendall(raw)
        client.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = client.recv(4096)
            if not chunk: break
            chunks.append(chunk)
    return json.loads(b"".join(chunks))

def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        work = pathlib.Path(temporary)
        gateway_socket = work / "gateway.sock"
        server_key = hashlib.sha256(b"server").hexdigest()
        client_key = hashlib.sha256(b"client").hexdigest()
        (work / "server-public-key").write_text(server_key + "\n", encoding="ascii")
        environment = os.environ | {
            "BEDROCK_PAIRING_GATEWAY_TEST_MODE": "1",
            "BEDROCK_PAIRING_GATEWAY_SOCKET": str(gateway_socket),
            "BEDROCK_PAIRING_GATEWAY_MANAGER": str(MANAGER),
            "BEDROCK_PAIRING_TEST_MODE": "1",
            "BEDROCK_PAIRING_STATE_DIR": str(work),
            "BEDROCK_PAIRING_SERVER_KEY": str(work / "server-public-key"),
            "BEDROCK_PAIRING_TEST_BOOT_ID": BOOT_ID,
            "BEDROCK_PAIRING_TEST_NOW": "100",
            "BEDROCK_PAIRING_TEST_WALL_NOW": "1000",
            "BEDROCK_PAIRING_TEST_ID": PAIRING_ID,
            "BEDROCK_PAIRING_TEST_DEVICE_ID": DEVICE_ID,
            "BEDROCK_PAIRING_TEST_CODE": CODE,
        }
        gateway = subprocess.Popen([sys.executable, str(GATEWAY)], env=environment)
        try:
            for _ in range(100):
                if gateway_socket.exists(): break
                if gateway.poll() is not None: raise AssertionError("pairing gateway exited")
                time.sleep(0.02)
            requested = exchange(gateway_socket, {"schema": 1, "action": "request", "client_public_key": client_key})
            assert requested["pairing_id"] == PAIRING_ID and requested["manual_code"] == CODE
            state = (work / "pairings.json").read_text(encoding="utf-8")
            assert CODE not in state and client_key not in state
            denied = exchange(gateway_socket, {"schema": 1, "action": "redeem", "pairing_id": PAIRING_ID, "manual_code": CODE, "client_public_key": client_key})
            assert denied == {"schema": 1, "status": "rejected", "error": "pairing-request-rejected"}
            subprocess.run([sys.executable, str(MANAGER), "approve", PAIRING_ID, f"APPROVE REMOTE DEVICE {PAIRING_ID}"], env=environment, check=True, capture_output=True)
            redeemed = exchange(gateway_socket, {"schema": 1, "action": "redeem", "pairing_id": PAIRING_ID, "manual_code": CODE, "client_public_key": client_key})
            assert redeemed["status"] == "redeemed" and redeemed["device_id"] == DEVICE_ID
            authorized = exchange(gateway_socket, {"schema": 1, "action": "authorize", "device_id": DEVICE_ID, "client_public_key": client_key})
            assert authorized == {"schema": 1, "status": "authorized", "device_id": DEVICE_ID, "session_target": f"bedrock-remote-device@{DEVICE_ID}.target"}
            assert json.loads((work / "pairings.json").read_text(encoding="utf-8"))["devices"][0]["last_seen_unix"] == 1000
            assert exchange(gateway_socket, {"schema": 1, "action": "authorize", "device_id": DEVICE_ID, "client_public_key": hashlib.sha256(b"wrong").hexdigest()}) == denied
            state = json.loads((work / "pairings.json").read_text(encoding="utf-8"))
            state["devices"][0]["revoked"] = True
            (work / "pairings.json").write_text(json.dumps(state, separators=(",", ":")) + "\n", encoding="utf-8")
            assert exchange(gateway_socket, {"schema": 1, "action": "authorize", "device_id": DEVICE_ID, "client_public_key": client_key}) == denied
            replay = exchange(gateway_socket, {"schema": 1, "action": "redeem", "pairing_id": PAIRING_ID, "manual_code": CODE, "client_public_key": client_key})
            assert replay == denied
            assert exchange(gateway_socket, b"x" * 1025) == denied
            assert exchange(gateway_socket, {"schema": 1, "action": "approve", "pairing_id": PAIRING_ID}) == denied
        finally:
            gateway.terminate()
            gateway.wait(timeout=3)
    print("Bounded remote pairing gateway tests passed.")

if __name__ == "__main__": main()
