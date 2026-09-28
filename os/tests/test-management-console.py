#!/usr/bin/python3
"""Exercise real dialog on a private PTY; never emit captured secret screens."""
import fcntl
import hashlib
import json
import os
import pathlib
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time

assert os.geteuid() == 0 and pathlib.Path("/.dockerenv").exists()
assert os.environ.get("BEDROCK_DISPOSABLE_SERVICE_TEST") == "1"
scenario = sys.argv[1] if len(sys.argv) > 1 else "issue"
assert scenario in ("issue", "decline", "failure")
source = pathlib.Path(__file__).resolve().parents[1] / "config/includes.chroot/usr/sbin/bedrock-setup-management"
destination = pathlib.Path("/usr/sbin/bedrock-setup-management")
shutil.copyfile(source, destination)
destination.chmod(0o755)
wizard = pathlib.Path("/usr/sbin/bedrock-first-run")
shutil.copyfile(source.with_name("bedrock-first-run"), wizard)
wizard.chmod(0o755)
marker = pathlib.Path("/var/lib/bedrock/setup/complete.json")
assert not marker.exists()
marker.parent.mkdir(exist_ok=True)
marker.write_text('{"setup_complete":true}\n')
marker_before = marker.read_bytes()
# Ordinary redirected execution must not issue credentials or start services.
assert subprocess.run([str(destination)], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                      stderr=subprocess.PIPE).returncode != 0
tokens_file = pathlib.Path("/var/lib/bedrock/api/tokens.json")
tokens_before = tokens_file.read_bytes()
if scenario == "failure":
    destination.chmod(0o600)  # Real exec failure; do not replace the helper with a fake.
child, terminal = pty.fork()
if child == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    os.execve(str(wizard), [str(wizard)], {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "TERM": "xterm"})


def screen_contains(needle):
    deadline = time.monotonic() + 10
    captured = b""
    while time.monotonic() < deadline:
        ready, _, _ = select.select([terminal], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(terminal, 65536)
            except OSError:
                break
            if not chunk:
                break
            captured += chunk
            if needle in captured:
                return captured
            if len(captured) > 262144:
                raise AssertionError("console output exceeded bound")
    # Do not include captured screens in failure diagnostics.
    raise AssertionError("expected console screen did not appear")


def issue_flow():
    screen_contains(b"Bedrock management access")
    os.write(terminal, b"\r")
    screen_contains(b"Access token name")
    os.write(terminal, b"console-acceptance\r")
    screen_contains(b"Issue administrator access")
    os.write(terminal, b"\r")
    displayed = screen_contains(b"will not be shown again")
    secret = re.search(rb"(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])", displayed)
    assert secret is not None, "token was not rendered in the real dialog"
    expected_hash = hashlib.sha256(secret.group()).hexdigest()
    del displayed, secret
    state = json.loads(pathlib.Path("/var/lib/bedrock/api/tokens.json").read_text())
    saved = next(item for item in state["tokens"] if item["name"] == "console-acceptance")
    assert saved["sha256"] == expected_hash and saved["revoked"] is False
    os.write(terminal, b"\r")
    screen_contains(b"Bedrock management access")
    assert not list(pathlib.Path("/run").glob("bedrock-management-*")), "temporary token display survived dismissal"
    os.write(terminal, b"\x1b\x1b")


try:
    screen_contains(b"Initial setup is already complete")
    os.write(terminal, b"\r")
    screen_contains(b"Management access")
    if scenario == "decline":
        os.write(terminal, b"\t\r")
    else:
        os.write(terminal, b"\r")
        if scenario == "failure":
            screen_contains(b"Management setup incomplete")
            os.write(terminal, b"\r")
        else:
            issue_flow()
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        ended, status = os.waitpid(child, os.WNOHANG)
        if ended:
            child = None
            assert os.waitstatus_to_exitcode(status) == 0
            break
        time.sleep(0.05)
    else:
        raise AssertionError("console did not exit after cancellation")
    if scenario == "issue":
        subprocess.run(["/usr/lib/bedrock/manage-api-tokens", "revoke", "console-acceptance"],
                       check=True, stdout=subprocess.DEVNULL)
    else:
        assert tokens_file.read_bytes() == tokens_before, "declined/failed handoff changed credentials"
    assert marker.read_bytes() == marker_before, "management handoff changed completed first-run state"
    print(f"Real management PTY passed: {scenario} handoff, unchanged setup state, redirected-input rejection.")
finally:
    os.close(terminal)
    if child is not None:
        try:
            os.killpg(child, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.waitpid(child, 0)
    marker.unlink()
    destination.chmod(0o755)
