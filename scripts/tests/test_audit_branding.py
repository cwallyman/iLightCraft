"""Audit portability and coverage in a tiny, isolated Git checkout."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2]


class BrandingAuditTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in (
            'scripts/audit-branding.py',
            'iLightCraft/Info.plist',
            'Engine/ffi/Cargo.toml',
            'iLightCraft.xcodeproj/project.pbxproj',
            'iLightCraft.xcodeproj/xcshareddata/xcschemes/iLightCraft.xcscheme',
        ):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / name, target)
        subprocess.run(['git', 'init', '--quiet', str(self.root)], check=True)
        tools = self.root / 'tools'
        tools.mkdir()
        unavailable = tools / 'rg'
        unavailable.write_text('#!/bin/sh\nexit 97\n')
        unavailable.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ.get('PATH', ''))

    def audit(self):
        return subprocess.run(
            [sys.executable, str(self.root / 'scripts/audit-branding.py')],
            cwd=self.root, env=self.environment, text=True, capture_output=True,
        )

    def test_audit_runs_without_ripgrep(self):
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_untracked_product_file_is_still_checked(self):
        (self.root / 'iLightCraft/Unexpected.swift').write_text('// ' + 'Un' + 'veil\n')
        result = self.audit()
        self.assertEqual(result.returncode, 1)
        self.assertIn('unexpected old product name', result.stdout)

    def test_deleted_tracked_path_is_not_a_shipping_file(self):
        name = 'iLightCraft/' + 'Un' + 'veil.swift'
        path = self.root / name
        path.write_text('// removed source\n')
        subprocess.run(['git', 'add', name], cwd=self.root, check=True)
        path.unlink()
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
