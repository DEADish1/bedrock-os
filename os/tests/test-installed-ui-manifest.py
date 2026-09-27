#!/usr/bin/python3
import copy
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

verifier = pathlib.Path(__file__).with_name("verify-installed-ui.py")
with tempfile.TemporaryDirectory(prefix="bedrock-ui-manifest-") as temporary:
    root = pathlib.Path(temporary)
    (root / "brand").mkdir()
    (root / "assets").mkdir()
    files = {"index.html": b"<!doctype html>", "brand/favicon.svg": b"<svg/>", "assets/rfb-test.js": b"console"}
    for name, data in files.items():
        (root / name).write_bytes(data)
    manifest = {"schema": 1, "source_commit": "a" * 40, "node_version": "v24.16.0", "lock_sha256": "b" * 64,
                "files": [{"path": name, "size_bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()} for name, data in files.items()]}

    def check(value, expected=True, commit="a" * 40):
        (root / "build-manifest.json").write_text(json.dumps(value))
        result = subprocess.run([sys.executable, str(verifier), str(root), commit], capture_output=True)
        assert (result.returncode == 0) == expected, result.stderr

    check(manifest)
    check(manifest, False, "c" * 40)
    for field, value in (("path", "../outside"), ("size_bytes", 999), ("sha256", "0" * 64)):
        bad = copy.deepcopy(manifest)
        bad["files"][0][field] = value
        check(bad, False)
    bad = copy.deepcopy(manifest)
    bad["files"].append(bad["files"][0])
    check(bad, False)
    (root / "unexpected.js").write_bytes(b"unmanifested")
    check(manifest, False)
    (root / "unexpected.js").unlink()
    (root / "index.html").write_bytes(b"modified contents")
    check(manifest, False)
    (root / "index.html").write_bytes(files["index.html"])
    (root / "brand").rename(root / "other-brand")
    (root / "brand").symlink_to(root / "other-brand", target_is_directory=True)
    check(manifest, False)
print("Installed UI manifest rejects corruption, wrong source, traversal, duplicates, extras and symlinks.")
