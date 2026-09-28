#!/usr/bin/python3
import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

source = pathlib.Path(__file__).resolve().parents[1] / "config/includes.chroot/usr/sbin/bedrock-setup-management"
loader = importlib.machinery.SourceFileLoader("management_setup", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
setup = importlib.util.module_from_spec(spec)
loader.exec_module(setup)


class ManagementSetupTests(unittest.TestCase):
    def test_activation_requires_live_token(self):
        with patch.object(setup, "run", return_value=SimpleNamespace(stdout=json.dumps({"tokens": [{"revoked": True}]}))) as command:
            with self.assertRaises(ValueError):
                setup.activate()
            self.assertEqual(command.call_count, 1)

    def test_start_before_enable(self):
        with patch.object(setup, "run", return_value=SimpleNamespace(stdout='{"tokens":[{"revoked":false}]}')) as command:
            setup.activate()
            self.assertEqual([call.args[0][1] for call in command.call_args_list], ["list", "start", "is-active", "enable"])

    def test_failed_start_does_not_enable(self):
        with patch.object(setup, "run", side_effect=[SimpleNamespace(stdout='{"tokens":[{"revoked":false}]}'), subprocess.CalledProcessError(1, "systemctl")]) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                setup.activate()
            self.assertEqual(command.call_count, 2)

    def test_invalid_name_does_not_issue(self):
        with patch.object(setup, "dialog", return_value=SimpleNamespace(returncode=0, stdout="../../bad")), patch.object(setup, "run") as command:
            with self.assertRaises(ValueError):
                setup.issue_token()
            command.assert_not_called()

    def test_cancel_confirmation_does_not_issue(self):
        with patch.object(setup, "dialog", side_effect=[SimpleNamespace(returncode=0, stdout="owner"), SimpleNamespace(returncode=1)]), patch.object(setup, "run") as command:
            setup.issue_token()
            command.assert_not_called()

    def check_display(self, cancelled):
        secret = "a" * 64
        temporary_factory = tempfile.TemporaryDirectory
        seen = []
        def screen(kind, title, message, *extra):
            self.assertNotIn(secret, str((kind, title, message, extra)))
            if kind == "--inputbox":
                return SimpleNamespace(returncode=0, stdout="owner")
            if kind == "--textbox":
                path = pathlib.Path(message)
                self.assertIn(secret, path.read_text())
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                seen.append(path)
                return SimpleNamespace(returncode=int(cancelled))
            return SimpleNamespace(returncode=0)
        with patch.object(setup.tempfile, "TemporaryDirectory", side_effect=lambda **kwargs: temporary_factory()), patch.object(setup, "dialog", side_effect=screen), patch.object(setup, "run", return_value=SimpleNamespace(stdout=json.dumps({"token": secret}))) as command:
            if cancelled:
                with self.assertRaises(ValueError):
                    setup.issue_token()
                self.assertEqual(command.call_args_list[-1].args[0], ["/usr/lib/bedrock/manage-api-tokens", "revoke", "owner"])
            else:
                setup.issue_token()
                self.assertEqual(command.call_count, 1)
            self.assertNotIn(secret, str(command.call_args_list))
        self.assertTrue(seen)
        self.assertFalse(seen[0].exists())

    def test_private_display_and_cleanup(self):
        self.check_display(False)

    def test_revocation_warns_on_last_token(self):
        state = '{"tokens":[{"name":"owner","revoked":false},{"name":"old","revoked":true}]}'
        with patch.object(setup, "run", return_value=SimpleNamespace(stdout=state)) as command, patch.object(setup, "dialog", side_effect=[SimpleNamespace(returncode=0, stdout="owner"), SimpleNamespace(returncode=0), SimpleNamespace(returncode=0)]) as screen:
            setup.revoke_token()
            self.assertIn("LAST active token", screen.call_args_list[1].args[2])
            self.assertNotIn("old", screen.call_args_list[0].args)
            self.assertEqual(command.call_args_list[-1].args[0], ["/usr/lib/bedrock/manage-api-tokens", "revoke", "owner"])

    def test_revocation_cancel_does_not_mutate(self):
        with patch.object(setup, "run", return_value=SimpleNamespace(stdout='{"tokens":[{"name":"owner","revoked":false}]}')) as command, patch.object(setup, "dialog", side_effect=[SimpleNamespace(returncode=0, stdout="owner"), SimpleNamespace(returncode=1)]):
            setup.revoke_token()
            self.assertEqual(command.call_count, 1)

    def test_revocation_rejects_unlisted_selection(self):
        with patch.object(setup, "run", return_value=SimpleNamespace(stdout='{"tokens":[{"name":"owner","revoked":false}]}')) as command, patch.object(setup, "dialog", return_value=SimpleNamespace(returncode=0, stdout="other")):
            with self.assertRaises(ValueError):
                setup.revoke_token()
            self.assertEqual(command.call_count, 1)

    def test_display_cancel_revokes_token(self):
        self.check_display(True)


if __name__ == "__main__":
    unittest.main()
