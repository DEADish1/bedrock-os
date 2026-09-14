#!/usr/bin/python3
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import socket
import struct
import tempfile
import threading

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import x25519
from noise.connection import Keypair, NoiseConnection

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "os/config/includes.chroot/usr/lib/bedrock/bedrock-noise-transport"


def load_tool(private: pathlib.Path, gateway: pathlib.Path, api_socket: pathlib.Path, api_token: pathlib.Path):
    os.environ["BEDROCK_NOISE_PRIVATE_KEY"] = str(private)
    os.environ["BEDROCK_NOISE_GATEWAY"] = str(gateway)
    os.environ["BEDROCK_NOISE_API_SOCKET"] = str(api_socket)
    os.environ["BEDROCK_NOISE_API_TOKEN_FILE"] = str(api_token)
    loader = importlib.machinery.SourceFileLoader("bedrock_noise_transport", str(TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def frame(value: bytes) -> bytes:
    return struct.pack("!I", len(value)) + value


def receive_frame(stream) -> bytes:
    size = struct.unpack("!I", stream.read(4))[0]
    return stream.read(size)


def gateway_once(path: pathlib.Path, seen: list[dict], ready: threading.Event) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(path))
        server.listen(1)
        server.settimeout(2)
        ready.set()
        try:
            connection, _ = server.accept()
        except TimeoutError:
            return
        with connection:
            raw = b""
            while True:
                chunk = connection.recv(2048)
                if not chunk:
                    break
                raw += chunk
            value = json.loads(raw)
            seen.append(value)
            connection.sendall(json.dumps({"schema": 1, "status": "accepted", "action": value["action"]},
                                          separators=(",", ":")).encode() + b"\n")


def api_once(path: pathlib.Path, seen: list[bytes], ready: threading.Event) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(path)); server.listen(1); ready.set()
        connection, _ = server.accept()
        with connection:
            raw = b""
            while b"\r\n\r\n" not in raw:
                raw += connection.recv(4096)
            seen.append(raw)
            body = b'{"schema":1,"status":"ok"}'
            connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nETag: \"safe\"\r\nContent-Length: " +
                               str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)


def exchange(module, private_raw: bytes, request: dict, corrupt: str | None = None,
             required_device: str | None = None) -> tuple[dict | None, list[dict]]:
    seen: list[dict] = []
    ready = threading.Event()
    gateway = threading.Thread(target=gateway_once, args=(module.GATEWAY, seen, ready), daemon=True)
    gateway.start()
    ready.wait(2)
    left, right = socket.socketpair()
    server_error = []

    def server() -> None:
        try:
            with left, left.makefile("rb", buffering=0) as incoming, left.makefile("wb", buffering=0) as outgoing:
                module.serve(incoming, outgoing, required_device)
        except Exception as error:
            server_error.append(error)

    worker = threading.Thread(target=server)
    worker.start()
    with right, right.makefile("rb", buffering=0) as incoming, right.makefile("wb", buffering=0) as outgoing:
        noise = NoiseConnection.from_name(module.PROTOCOL)
        noise.set_as_initiator()
        noise.set_prologue(module.PROLOGUE)
        noise.set_keypair_from_private_bytes(Keypair.STATIC, private_raw)
        noise.start_handshake()
        outgoing.write(frame(bytes(noise.write_message()))); outgoing.flush()
        noise.read_message(receive_frame(incoming))
        outgoing.write(frame(bytes(noise.write_message()))); outgoing.flush()
        session_id = noise.get_handshake_hash()[:16]
        encrypted = bytearray(module.encrypt_record(noise, request, session_id, module.CLIENT_TO_SERVER, 0,
                                                    module.RECORD_CONTROL))
        if corrupt == "ciphertext":
            encrypted[-1] ^= 1
        elif corrupt == "session":
            encrypted[1] ^= 1
        elif corrupt == "direction":
            encrypted[17] = module.SERVER_TO_CLIENT
        elif corrupt == "type":
            encrypted[26] = module.RECORD_API
        outgoing.write(frame(bytes(encrypted))); outgoing.flush()
        right.shutdown(socket.SHUT_WR)
        try:
            response = module.decrypt_record(noise, receive_frame(incoming), session_id, module.SERVER_TO_CLIENT,
                                             0, module.RECORD_CONTROL)
        except (EOFError, OSError, struct.error):
            response = None
    worker.join(3)
    gateway.join(3)
    assert not worker.is_alive()
    if corrupt or request.get("client_public_key") == "00" * 32 or (
            required_device is not None and request.get("device_id") != required_device):
        assert server_error and not seen and response is None
    else:
        assert not server_error
    return response, seen


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        work = pathlib.Path(temporary)
        server_private = x25519.X25519PrivateKey.generate()
        pem = server_private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                           serialization.NoEncryption())
        private = work / "server-private-key.pem"
        private.write_bytes(pem)
        private.chmod(0o600)
        api_token = work / "api-token"
        api_token.write_text("a" * 64 + "\n", encoding="ascii")
        module = load_tool(private, work / "gateway.sock", work / "api.sock", api_token)

        client = x25519.X25519PrivateKey.generate()
        client_raw = client.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                                          serialization.NoEncryption())
        client_public = client.public_key().public_bytes(serialization.Encoding.Raw,
                                                         serialization.PublicFormat.Raw).hex()
        response, seen = exchange(module, client_raw, {"schema": 1, "action": "request"})
        assert response == {"schema": 1, "status": "accepted", "action": "request"}
        assert seen == [{"schema": 1, "action": "request", "client_public_key": client_public}]

        response, _ = exchange(module, client_raw, {"schema": 1, "action": "authorize",
                                                    "device_id": "42345678-1234-4123-8123-123456789abc",
                                                    "client_public_key": "00" * 32})
        assert response is None
        for corruption in ("ciphertext", "session", "direction", "type"):
            response, _ = exchange(module, client_raw, {"schema": 1, "action": "redeem"}, corrupt=corruption)
            assert response is None
        device = "42345678-1234-4123-8123-123456789abc"
        response, seen = exchange(module, client_raw, {"schema": 1, "action": "authorize", "device_id": device},
                                  required_device=device)
        assert response and seen[0]["device_id"] == device
        response, _ = exchange(module, client_raw, {"schema": 1, "action": "authorize",
                                                    "device_id": "62345678-1234-4123-8123-123456789abc"},
                               required_device=device)
        assert response is None

        api_seen: list[bytes] = []
        ready = threading.Event()
        api = threading.Thread(target=api_once, args=(module.API_SOCKET, api_seen, ready))
        api.start(); ready.wait(2)
        proxied = module.api_exchange({"schema": 1, "action": "api", "method": "GET",
                                      "path": "/api/v1/health", "headers": {}, "body": ""},
                                     module.load_api_token())
        api.join(2)
        assert proxied == {"schema": 1, "status": 200, "content_type": "application/json",
                           "etag": '"safe"', "body": "eyJzY2hlbWEiOjEsInN0YXR1cyI6Im9rIn0="}
        assert b"Authorization: Bearer " + b"a" * 64 in api_seen[0]
        try:
            module.api_exchange({"schema": 1, "action": "api", "method": "GET", "path": "/api/v1/health",
                                 "headers": {"Authorization": "Bearer exposed"}, "body": ""}, "a" * 64)
            raise AssertionError("client-supplied authorization was accepted")
        except module.ProtocolError:
            pass
    print("Noise XX transport identity-binding tests passed.")


if __name__ == "__main__":
    main()
