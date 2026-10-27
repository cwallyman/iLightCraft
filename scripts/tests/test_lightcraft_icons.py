#!/usr/bin/env python3
"""Validate desktop source provenance and all native vector icon references."""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class LightCraftIconsTests(unittest.TestCase):
    def test_source_and_complete_catalog(self):
        source = ROOT / 'scripts/icon-tools/lightcraft-icons.rs'
        manifest = json.loads((source.parent / 'source.json').read_text())
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), manifest['sha256'])
        desktop = re.findall(r'^    (\w+),', source.read_text().split('struct Pen')[0], re.M)
        self.assertTrue(set(desktop).issubset(manifest['icons']))
        for name in manifest['icons']:
            folder = ROOT / f'iLightCraft/Resources/Assets.xcassets/LightCraft-{name}.imageset'
            catalog = json.loads((folder / 'Contents.json').read_text())
            self.assertTrue(catalog['properties']['preserves-vector-representation'])
            self.assertEqual(catalog['properties']['template-rendering-intent'], 'template')
            pdf = (folder / 'icon.pdf').read_bytes()
            self.assertTrue(pdf.startswith(b'%PDF-'))
            self.assertIn(b'/MediaBox [ 0 0 20 20 ]', pdf)

    def test_all_ui_references_resolve_and_no_sf_symbols_remain(self):
        catalog = ROOT / 'iLightCraft/Resources/Assets.xcassets'
        for file in (ROOT / 'iLightCraft').rglob('*.swift'):
            source = file.read_text()
            self.assertNotRegex(source, r'\b(?:systemName|systemImage)\s*:', str(file))
            for name in re.findall(r'"(LightCraft-[A-Za-z]+)"', source):
                self.assertTrue((catalog / f'{name}.imageset/Contents.json').exists(), f'{file}: {name}')
            for name in re.findall(r'lightCraftIcon\s*:\s*"([^"]+)"', source):
                self.assertTrue(name.startswith('LightCraft-'), f'{file}: {name}')

if __name__ == '__main__':
    unittest.main()
