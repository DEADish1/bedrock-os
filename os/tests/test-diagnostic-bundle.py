#!/usr/bin/python3
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "os/config/includes.chroot/usr/sbin/bedrock-diagnostic-bundle"
CONSENT = "CREATE REDACTED DIAGNOSTIC BUNDLE"

def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        work = pathlib.Path(temporary)
        source = work / "root"
        fixtures = {
            "etc/bedrock-release": "BEDROCK_VERSION=0.2.0-dev\n",
            "var/lib/bedrock/hardware/inventory.json": json.dumps({"schema": 1, "hostname": "private-home", "serial": "ABC123", "nic": {"mac": "aa:bb:cc:dd:ee:ff", "state": "up"}}),
            "var/lib/bedrock/storage/health.json": json.dumps({"schema": 1, "overall": "healthy", "device_path": "/dev/sda"}),
            "var/lib/bedrock/update/last-check.json": json.dumps({"schema": 1, "status": "current", "token": "x"}),
        }
        for relative, content in fixtures.items():
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        output = work / "bundle.tar.gz"
        environment = os.environ | {"BEDROCK_DIAGNOSTIC_TEST_MODE": "1", "BEDROCK_DIAGNOSTIC_ROOT": str(source), "BEDROCK_DIAGNOSTIC_TEST_NOW": "1000"}
        denied = subprocess.run([sys.executable, str(TOOL), "yes", str(output)], env=environment, capture_output=True, text=True)
        assert denied.returncode != 0 and not output.exists()
        subprocess.run([sys.executable, str(TOOL), CONSENT, str(output)], env=environment, check=True, capture_output=True, text=True)
        if os.name != "nt":
            assert output.stat().st_mode & 0o077 == 0
        with tarfile.open(output, "r:gz") as bundle:
            names = set(bundle.getnames())
            assert names == {"diagnostics/manifest.json", "diagnostics/release.txt", "diagnostics/hardware.json", "diagnostics/storage-health.json", "diagnostics/updates.json"}
            combined = b"".join(bundle.extractfile(name).read() for name in names).decode()
            assert "private-home" not in combined and "ABC123" not in combined and "aa:bb:cc:dd:ee:ff" not in combined and "/dev/sda" not in combined
            assert '"redacted":true' in combined and '"overall":"healthy"' in combined
        repeated = subprocess.run([sys.executable, str(TOOL), CONSENT, str(output)], env=environment, capture_output=True, text=True)
        assert repeated.returncode != 0
    print("Bedrock consent-gated redacted diagnostic bundle tests passed.")

if __name__ == "__main__":
    main()
