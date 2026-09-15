#!/usr/bin/python3
import array
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import socket
import ssl
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "os/config/includes.chroot/usr/lib/bedrock/bedrock-relay-connector"
SERVER_ROUTE = "12345678-1234-4123-8123-123456789abc"
SESSION = "52345678-1234-4123-8123-123456789abc"
TOKEN = "relay_test_token_abcdefghijklmnopqrstuvwxyz0123456789"


def load_tool(config: pathlib.Path, token: pathlib.Path, broker: pathlib.Path, certificate: pathlib.Path):
    os.environ.update(BEDROCK_RELAY_CONFIG=str(config), BEDROCK_RELAY_TOKEN=str(token),
                      BEDROCK_RELAY_BROKER=str(broker), BEDROCK_RELAY_CA_FILE=str(certificate))
    loader = importlib.machinery.SourceFileLoader("bedrock_relay_connector", str(TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec); loader.exec_module(module)
    return module


def broker_once(path: pathlib.Path, seen: list[dict], ready: threading.Event) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as server:
        server.bind(str(path)); server.listen(1); ready.set()
        connection, _ = server.accept()
        with connection:
            raw, ancillary, _flags, _ = connection.recvmsg(1024, socket.CMSG_SPACE(array.array("i").itemsize))
            descriptors = array.array("i")
            for level, kind, value in ancillary:
                if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    descriptors.frombytes(value[:descriptors.itemsize])
            assert len(descriptors) == 1
            seen.append(json.loads(raw))
            connection.sendall(b'{"schema":1,"status":"accepted"}\n')
            stream = socket.socket(fileno=descriptors[0])
            with stream:
                payload = stream.recv(1024)
                stream.sendall(b"echo:" + payload)


def relay_once(module, port: list[int], certificate: pathlib.Path, key: pathlib.Path,
               seen: list[tuple[int, bytes, bytes]], ready: threading.Event) -> None:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["bedrock-relay/1"])
    context.load_cert_chain(str(certificate), str(key))
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0)); server.listen(1); port.append(server.getsockname()[1]); ready.set()
        raw, _ = server.accept()
        with context.wrap_socket(raw, server_side=True) as connection:
            lock = threading.Lock()
            kind, stream_id, payload = module.receive_frame(connection); seen.append((kind, stream_id, payload))
            module.send_frame(connection, lock, module.REGISTERED, module.ZERO_STREAM)
            identifier = bytes.fromhex("11" * 16)
            route = json.dumps({"schema": 1, "mode": "pairing", "session_id": SESSION},
                               separators=(",", ":")).encode("ascii")
            module.send_frame(connection, lock, module.OPEN, identifier, route)
            module.send_frame(connection, lock, module.DATA, identifier, b"opaque-noise-ciphertext")
            while True:
                item = module.receive_frame(connection); seen.append(item)
                if item[0] == module.CLOSE:
                    break


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        work = pathlib.Path(temporary)
        certificate, key = work / "relay.crt", work / "relay.key"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                        "-keyout", str(key), "-out", str(certificate)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        config, token = work / "relay.json", work / "relay-token"
        token.write_text(TOKEN + "\n", encoding="ascii")
        broker_path = work / "broker.sock"
        module = load_tool(config, token, broker_path, certificate)
        broker_seen: list[dict] = []; broker_ready = threading.Event()
        broker = threading.Thread(target=broker_once, args=(broker_path, broker_seen, broker_ready)); broker.start(); broker_ready.wait(2)
        relay_seen: list[tuple[int, bytes, bytes]] = []; relay_ready = threading.Event(); port: list[int] = []
        relay = threading.Thread(target=relay_once, args=(module, port, certificate, key, relay_seen, relay_ready)); relay.start(); relay_ready.wait(2)
        config.write_text(json.dumps({"schema": 1, "host": "localhost", "port": port[0],
                                     "server_route": SERVER_ROUTE, "connect_timeout_seconds": 5,
                                     "idle_timeout_seconds": 30}), encoding="utf-8")
        try:
            module.run_once(module.settings(), module.tls_context())
        except module.RelayError:
            pass
        relay.join(3); broker.join(3)
        assert not relay.is_alive() and not broker.is_alive()
        registration = json.loads(relay_seen[0][2])
        assert registration == {"schema": 1, "server_route": SERVER_ROUTE, "authorization": TOKEN}
        assert broker_seen == [{"schema": 1, "mode": "pairing", "session_id": SESSION}]
        assert any(kind == module.DATA and payload == b"echo:opaque-noise-ciphertext" for kind, _stream, payload in relay_seen)
        assert all(b"opaque-noise-ciphertext" not in payload for kind, _stream, payload in relay_seen if kind in {module.REGISTER, module.OPEN})
        context = module.tls_context()
        assert context.minimum_version == ssl.TLSVersion.TLSv1_3 and context.maximum_version == ssl.TLSVersion.TLSv1_3
    print("Outbound TLS 1.3 relay connector tests passed.")


if __name__ == "__main__":
    main()
