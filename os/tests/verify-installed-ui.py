#!/usr/bin/python3
"""Verify a staged or extracted UI bundle against its build manifest."""
import hashlib
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
assert root.is_dir() and not root.is_symlink()
manifest_path = root / "build-manifest.json"
assert manifest_path.is_file() and not manifest_path.is_symlink()
manifest = json.loads(manifest_path.read_text())
assert set(manifest) == {"schema", "source_commit", "node_version", "lock_sha256", "files"}
assert manifest["schema"] == 1 and re.fullmatch(r"[0-9a-f]{40}", manifest["source_commit"])
if len(sys.argv) > 2:
    assert manifest["source_commit"] == sys.argv[2], "UI source commit differs from image source"
assert manifest["node_version"] == "v24.16.0" and re.fullmatch(r"[0-9a-f]{64}", manifest["lock_sha256"])
assert isinstance(manifest["files"], list) and 1 <= len(manifest["files"]) <= 1024
expected = set()
for entry in manifest["files"]:
    assert set(entry) == {"path", "size_bytes", "sha256"}
    name = entry["path"]
    assert isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*", name)
    assert not any(part in {".", ".."} for part in name.split("/")) and name not in expected
    expected.add(name)
    source = root / name
    assert all(not parent.is_symlink() for parent in source.parents if parent != root.parent)
    assert source.is_file() and not source.is_symlink()
    assert type(entry["size_bytes"]) is int and source.stat().st_size == entry["size_bytes"]
    assert hashlib.sha256(source.read_bytes()).hexdigest() == entry["sha256"]
actual = set()
for source in root.rglob("*"):
    assert not source.is_symlink()
    if source.is_file() and source != manifest_path:
        actual.add(source.relative_to(root).as_posix())
assert actual == expected and {"index.html", "brand/favicon.svg"} <= expected
assert any(name.startswith("assets/rfb-") and name.endswith(".js") for name in expected)
print("Installed UI file manifest verified.")
