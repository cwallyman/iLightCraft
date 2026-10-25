#!/usr/bin/env python3
"""Fetch pinned permissive model weights and build the local Core ML masking packages.
Build-time dependencies: scripts/mask-model-requirements.txt (install in a venv).
No photograph is read or uploaded. Generated model packages are gitignored.
"""
import hashlib
import http.client
from pathlib import Path
import shutil
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'iLightCraft/Resources/MaskModels'
SKY = 'https://huggingface.co/twistlabs/fotometis-sky/resolve/97dfe50bf3fe4dc02badea287512afaf4ce857c2/SkySegSmall.mlpackage/'
FILES = [
    ('Manifest.json', 617, '2ef47fc3ea776f1f11b8870284fe15974e6d8be96515d071851df0d407791677'),
    ('Data/com.apple.CoreML/model.mlmodel', 256359, 'f12a39fe104d0a5d2285820d322d9697de5a5011ee355132cbc01822e9d1a06f'),
    ('Data/com.apple.CoreML/weights/weight.bin', 2268608, '5df3feebcc15a77480fabb9896b96036e5acc38dc043af414f09dc5b1d296efb'),
]


def fetch(url, destination, size, digest):
    # Ask the Hub for file bytes rather than its preview response. The revision,
    # exact length and digest remain mandatory even after a retry or redirect.
    download_url = url + ('&' if '?' in url else '?') + 'download=true'
    request = urllib.request.Request(download_url, headers={
        'User-Agent': 'iLightCraft-model-build/1',
        'Accept': 'application/octet-stream',
        'Accept-Encoding': 'identity',
        'Cache-Control': 'no-cache',
    })
    for attempt in range(1, 4):
        try:
            chunks = []
            total = 0
            with urllib.request.urlopen(request, timeout=90) as response:
                while total <= size:
                    chunk = response.read(min(1024 * 1024, size + 1 - total))
                    if not chunk:
                        break
                    chunks.append(chunk)
                    total += len(chunk)
            data = b''.join(chunks)
            actual_digest = hashlib.sha256(data).hexdigest()
            if len(data) != size or actual_digest != digest:
                raise ValueError(
                    f'expected {size} bytes / SHA-256 {digest}; '
                    f'received {len(data)} bytes / SHA-256 {actual_digest}'
                )
        except (OSError, http.client.HTTPException, ValueError) as error:
            print(f'Model download attempt {attempt}/3 rejected for {destination.name}: {error}', flush=True)
            if attempt == 3:
                raise ValueError(f'Could not obtain verified model file {destination.name}: {error}') from error
            time.sleep(attempt * 2)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if all((OUT / name).exists() for name in ('SkySegSmall.mlpackage', 'SkinSeg.mlpackage')):
        print('Mask model packages already prepared.')
        return
    import torch
    import onnx
    import coremltools as ct
    from onnx2torch import convert
    with tempfile.TemporaryDirectory(prefix='ilightcraft-masks-') as temporary:
        work = Path(temporary)
        sky = work / 'SkySegSmall.mlpackage'
        for name, size, digest in FILES:
            fetch(SKY + name, sky / name, size, digest)
        source = work / 'skin.onnx'
        fetch('https://huggingface.co/senty-au/selfie_multiclass_256x256-ONNX/resolve/6db8421a7150ac20558f2c24675078eb3a1a04d0/onnx/model.onnx',
              source, 16454560, '35ec1ecd9ee7f85073c99c00020b7f6751b69506eeacf683bc8665f6117f85b0')
        graph = convert(onnx.load(source)).eval()
        sample = torch.zeros((1, 256, 256, 3))
        with torch.no_grad():
            traced = torch.jit.trace(graph, sample)
        model = ct.convert(traced, inputs=[ct.TensorType(name='image', shape=sample.shape)],
                           outputs=[ct.TensorType(name='skinClasses')],
                           minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT32)
        model.short_description = 'Google MediaPipe Selfie Multiclass: RGB [0,1] NHWC input; six output logits. Apply softmax.'
        model.author = 'Google LLC; ONNX conversion by senty-au; Core ML conversion for iLightCraft'
        model.license = 'Apache-2.0'
        model.save(str(work / 'SkinSeg.mlpackage'))
        for name in ('SkySegSmall.mlpackage', 'SkinSeg.mlpackage'):
            if not (OUT / name).exists():
                shutil.copytree(work / name, OUT / name)
    print('Pinned sky and skin packages prepared for Xcode compilation.')


if __name__ == '__main__':
    main()
