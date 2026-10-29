#!/usr/bin/env python3
"""Fetch the pinned, licensed depth model for inclusion in native app builds."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'iLightCraft/Resources/MaskModels/DepthAnythingV2SmallF16.mlpackage'
BASE = 'https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/cfef6f6f2a70783dedc0bfae40cecbc2052285d3/DepthAnythingV2SmallF16.mlpackage/'
FILES = [
    ('Manifest.json', 617, '2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7'),
    ('Data/com.apple.CoreML/model.mlmodel', 399433, '44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042'),
    ('Data/com.apple.CoreML/weights/weight.bin', 49419072, 'fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed'),
]


def valid(directory):
    for name, size, digest in FILES:
        path = directory / name
        if not path.is_file() or path.stat().st_size != size:
            return False
        with path.open('rb') as file:
            if hashlib.file_digest(file, 'sha256').hexdigest() != digest:
                return False
    return True


def main():
    if OUT.exists():
        if not valid(OUT):
            raise SystemExit(f'Existing depth model is invalid: {OUT}. Move it aside and rerun.')
        print('Pinned depth model already prepared.')
        return
    spec = importlib.util.spec_from_file_location('mask_model_fetch', ROOT / 'scripts/build-mask-models.py')
    if spec is None or spec.loader is None:
        raise SystemExit('Cannot load the model download helper.')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ilightcraft-depth-', dir=OUT.parent) as tmp:
        staged = Path(tmp) / OUT.name
        for name, size, digest in FILES:
            helper.fetch(BASE + name, staged / name, size, digest)
        if not valid(staged):
            raise SystemExit('Depth model verification failed.')
        shutil.move(str(staged), str(OUT))
    print('Pinned depth model prepared for Xcode.')


if __name__ == '__main__':
    main()
