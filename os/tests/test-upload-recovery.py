#!/usr/bin/python3
"""Validate legacy staging recovery and reject ambiguous candidate state."""
import hashlib
import json
import os
import pathlib
import runpy
import tempfile

API = pathlib.Path(__file__).resolve().parents[1] / "config/includes.chroot/usr/lib/bedrock/bedrock-api"


def main():
    api = runpy.run_path(str(API))
    recover = api["recover_interrupted_uploads"]
    scope = recover.__globals__
    with tempfile.TemporaryDirectory(prefix="bedrock-upload-recovery-") as temporary:
        root = pathlib.Path(temporary)
        scope["TASKS"] = root / "absent-tasks.json"
        contents = b"legacy-upload-data"
        manifest = {"schema": 1, "name": "legacy", "type": "iso", "sha256": hashlib.sha256(contents).hexdigest(), "size_bytes": len(contents)}

        def fixture(name):
            directory = root / name
            directory.mkdir()
            scope["UPLOADS"] = directory
            (directory / ".legacy.import.lock").touch(mode=0o600)
            (directory / ".legacy.discard.data").write_bytes(contents)
            (directory / ".legacy.discard.json").write_text(json.dumps(manifest))
            return directory

        def snapshot(directory):
            return {path.name: ("link", os.readlink(path)) if path.is_symlink() else ("file", path.read_bytes(), path.stat().st_mode)
                    for path in directory.iterdir()}

        for phase in ("data-renamed", "both-renamed", "data-deleted", "data-linked", "metadata-linked"):
            directory = fixture(phase)
            if phase == "data-renamed":
                (directory / ".legacy.discard.json").rename(directory / "legacy.json")
            elif phase == "data-deleted":
                (directory / ".legacy.discard.data").unlink()
            elif phase == "data-linked":
                os.link(directory / ".legacy.discard.data", directory / "legacy.iso")
            elif phase == "metadata-linked":
                (directory / ".legacy.discard.data").rename(directory / "legacy.iso")
                os.link(directory / ".legacy.discard.json", directory / "legacy.json")
            recover()
            if phase == "data-deleted":
                assert not list(directory.iterdir())
            else:
                assert {path.name for path in directory.iterdir()} == {"legacy.iso", "legacy.json"}
                assert (directory / "legacy.iso").read_bytes() == contents
                assert json.loads((directory / "legacy.json").read_text()) == manifest
            before = snapshot(directory)
            recover()
            assert snapshot(directory) == before

        original_sync = scope["sync_upload_directory"]
        for phase in range(1, 8):
            directory = fixture(f"recovery-interrupted-{phase}")
            calls = 0
            def interrupted_sync():
                nonlocal calls
                original_sync()
                calls += 1
                if calls == phase:
                    raise OSError("simulated recovery interruption")
            scope["sync_upload_directory"] = interrupted_sync
            try:
                recover()
            except OSError:
                pass
            else:
                raise AssertionError("recovery interruption was not reached")
            finally:
                scope["sync_upload_directory"] = original_sync
            recover()
            assert {path.name for path in directory.iterdir()} == {"legacy.iso", "legacy.json"}
            assert (directory / "legacy.iso").read_bytes() == contents
            assert json.loads((directory / "legacy.json").read_text()) == manifest

        for unsafe in ("missing-lock", "indirect-lock", "indirect-data", "conflicting-data", "conflicting-metadata", "invalid-metadata"):
            directory = fixture(unsafe)
            if unsafe in {"missing-lock", "indirect-lock"}:
                (directory / ".legacy.import.lock").unlink()
                if unsafe == "indirect-lock":
                    (directory / ".legacy.import.lock").symlink_to(root / "absent-lock")
            elif unsafe == "indirect-data":
                (directory / ".legacy.discard.data").unlink()
                (directory / ".legacy.discard.data").symlink_to(root / "absent-data")
            elif unsafe == "conflicting-data":
                (directory / "legacy.iso").write_bytes(contents)
            elif unsafe == "conflicting-metadata":
                (directory / "legacy.json").write_text(json.dumps(manifest))
            else:
                (directory / ".legacy.discard.json").write_text("{}")
            before = snapshot(directory)
            try:
                recover()
            except (OSError, ValueError):
                pass
            else:
                raise AssertionError(f"accepted unsafe legacy recovery: {unsafe}")
            assert snapshot(directory) == before

        for invalid in ("missing-data", "wrong-size", "bad-json", "indirect-metadata"):
            directory = root / invalid
            directory.mkdir()
            scope["UPLOADS"] = directory
            (directory / ".legacy.upload.lock").touch()
            (directory / ".legacy.upload.partial").write_bytes(b"evidence")
            metadata = directory / "legacy.json"
            metadata.write_text(json.dumps(manifest))
            if invalid == "wrong-size":
                (directory / "legacy.iso").write_bytes(b"short")
            elif invalid == "bad-json":
                metadata.write_text("{")
            elif invalid == "indirect-metadata":
                metadata.unlink()
                metadata.symlink_to(root / "absent-metadata")
            before = snapshot(directory)
            try:
                recover()
            except (OSError, ValueError):
                pass
            else:
                raise AssertionError(f"accepted corrupt upload metadata: {invalid}")
            assert snapshot(directory) == before, "recovery discarded evidence before validating the candidate"
    print("Legacy discard and upload metadata recovery tests passed.")


if __name__ == "__main__":
    main()
