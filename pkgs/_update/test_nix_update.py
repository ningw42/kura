"""Regression tests for the local Mic92/nix-update#687 workaround."""

import json
import subprocess
import unittest
from unittest.mock import patch

from nix_update.options import Options, get_flake_store_path


class FlakePrefetchTests(unittest.TestCase):
    def prefetch_result(self, path, **metadata):
        return subprocess.CompletedProcess(
            [], 0, stdout=json.dumps({"storePath": path, **metadata})
        )

    @patch("nix_update.options.subprocess.run")
    def test_materializes_the_source_instead_of_only_reading_metadata(self, run):
        run.return_value = self.prefetch_result("/nix/store/example-source")

        self.assertEqual(get_flake_store_path("/checkout"), "/nix/store/example-source")
        run.assert_called_once_with(
            ["nix", "flake", "prefetch", "--json"],
            cwd="/checkout",
            capture_output=True,
            text=True,
            check=True,
        )

    @patch("nix_update.options.subprocess.run")
    def test_preserves_subdirectory_flakes(self, run):
        run.return_value = self.prefetch_result(
            "/nix/store/example-source", locked={"dir": "nested/flake"}
        )

        self.assertEqual(
            get_flake_store_path("/checkout/nested/flake"),
            "/nix/store/example-source/nested/flake",
        )

    @patch("nix_update.options.subprocess.run")
    def test_package_evaluations_refresh_the_snapshot_after_edits(self, run):
        run.side_effect = [
            self.prefetch_result("/nix/store/before-source"),
            self.prefetch_result("/nix/store/after-source"),
        ]
        # This directory exists, as required by get_flake_import_path().
        options = Options(attribute="example", flake=True, import_path=".")

        self.assertIn('getFlake "/nix/store/before-source"', options.get_package())
        self.assertIn('getFlake "/nix/store/after-source"', options.get_package())
        self.assertEqual(run.call_count, 2)
        for call in run.call_args_list:
            self.assertEqual(call.args[0], ["nix", "flake", "prefetch", "--json"])

    @patch("nix_update.options.subprocess.run")
    def test_non_flake_fallback(self, run):
        run.side_effect = subprocess.CalledProcessError(1, ["nix", "flake", "prefetch"])

        self.assertIsNone(get_flake_store_path("/not-a-flake"))


if __name__ == "__main__":
    unittest.main()
