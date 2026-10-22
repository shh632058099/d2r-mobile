import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from input_config import download_file


class PrivateOutputAssetTests(unittest.TestCase):
    def test_private_output_release_asset_uses_authenticated_gh_download(self):
        payload = b"prepared private asset"

        def fake_run(argv, stdout, stderr=None):
            stdout.write(payload)
            return SimpleNamespace(returncode=0)

        environment = {
            "GITHUB_REPOSITORY": "shh632058099/d2r-mobile",
            "OUTPUT_REPOSITORY": "owner/private-build",
            "GH_TOKEN": "test-token",
        }
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, environment), \
                patch("subprocess.run", side_effect=fake_run) as run:
            destination = Path(temporary) / "prepared.zip"
            download_file(
                "https://api.github.com/repos/owner/private-build/releases/assets/12345",
                destination,
            )
            self.assertEqual(destination.read_bytes(), payload)
            argv = run.call_args.args[0]
            self.assertEqual(argv[:3], ["gh", "api", "repos/owner/private-build/releases/assets/12345"])
            self.assertIn("Accept: application/octet-stream", argv)


if __name__ == "__main__":
    unittest.main()
