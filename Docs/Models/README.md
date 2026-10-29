# Optional on-device models

Last updated: 2026-10-28. The depth, sky and skin models are bundled from pinned, gitignored build inputs; weights are never committed. Enhancement models are optional downloads.
The user chose on-device processing first. Hosted sharing remains separately configured future work.

## Sources and licenses

| Feature | Model / publisher | Immutable revision | License | Download |
|---|---|---|---|---|
| Relative depth | [Apple Core ML Depth Anything V2 Small F16](https://huggingface.co/apple/coreml-depth-anything-v2-small), original Depth Anything V2 Small by Lihe Yang and collaborators | `cfef6f6f2a70783dedc0bfae40cecbc2052285d3` | Apache-2.0 | 49,819,122 bytes across three package files |
| RGB denoise | [VincentGOURBIN Core ML RealESRGAN-x4v3-denoise](https://huggingface.co/VincentGOURBIN/RealESRGAN-CoreML), [original Real-ESRGAN by Xintao Wang and collaborators](https://github.com/xinntao/Real-ESRGAN) | `da0d01ce79946e6a62563eaf900ff9844af1f67f` | BSD-3-Clause | ZIP 2,286,246 bytes |
| RGB 2× enhancement | Same publisher, `RealESRGAN-x4v3` | Same revision | BSD-3-Clause | ZIP 2,286,340 bytes |

Only these specific general-purpose x4v3 variants are offered. Other models in a publisher's repository
can have different licenses. RawNIND/GPL weights, SAM weights and identity-recognition models are not enabled.
Apple Vision subject/person segmentation, classification, OCR and face detection use system models;
NaturalLanguage supplies optional local English sentence embeddings of labels/OCR. These do not identify people.

## Integrity pins

Bundled depth package `DepthAnythingV2SmallF16.mlpackage` (prepare with `python3 scripts/prepare-depth-model.py`):

| Relative path | Bytes | SHA-256 |
|---|---:|---|
| `Manifest.json` | 617 | `2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7` |
| `Data/com.apple.CoreML/model.mlmodel` | 399433 | `44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042` |
| `Data/com.apple.CoreML/weights/weight.bin` | 49419072 | `fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed` |

Enhancement ZIPs:

| Archive | SHA-256 |
|---|---|
| `RealESRGAN-x4v3-denoise.mlpackage.zip` | `a577c31ccc3025d84807f7e124d71656fb2cbbdc57c4c44d3ac2d9980da9c9c4` |
| `RealESRGAN-x4v3.mlpackage.zip` | `5a59e554794371b95fe61274b8a2040f1b3e274479abf15595dcdad0535afad4` |

Downloads cancel above pinned byte limits. Swift checks size/SHA before compilation; Rust independently
checks enhancement ZIP size/SHA and extracts only three fixed filenames with a 3 MiB-per-file bound.
A staged installation moves into the app-private model directory only after compilation succeeds.
Each installation includes its SOURCE.txt and license. Remove Downloaded Model deletes that model only.
Interrupted/corrupt downloads do not replace an installed model. Compilation is cancellable after the current
system compile operation finishes. A corrupt compiled cache reports an error; remove/re-download to recover.

## Processing contracts and privacy

All photo inference stays on the device. Model downloads contact Hugging Face and its redirected hosting/CDN;
the host sees ordinary request/network information, but receives no photo bytes, face crops or search queries.
No remote inference endpoint, account, secret or sharing backend is introduced.

RGB enhancement exports current SDR edits to opaque sRGB PNG. Its model input is planar float16 NCHW
`input: [1,3,256,256]`; output is `output: [1,3,1024,1024]`. Tiles have 40-pixel context on each side,
retaining a 176-pixel core. The 4× prediction is area-pooled to original dimensions for denoise or 2×
dimensions for Super Resolution. Output is a separate opaque 8-bit SDR PNG, capped at 80 MP. HDR editing
must be disabled explicitly. This is RGB restoration, not sensor-domain denoise or Raw Details. The tensor
contract was checked with Core ML metadata; model execution and output quality still need device acceptance.

The bundled depth model requires no download on the device. Depth inference uses a reduced current render and produces normalized relative depth, not metric distance.
Focus, range and blur strength produce a separate full-resolution half-float linear TIFF. It is a rendered
copy; the main Undo button returns to the source during the current editor session. Depth/blur parameters are not an editable layer on the copy. Bokeh shapes and painted depth
refinement remain future work. A normal 2D blur is not represented as a completed depth-model result.

Memory guards reject jobs exceeding estimated headroom and fail closed if available memory is unknown.
They are conservative estimates, not guarantees against every OS memory limit.
The private local analysis index is bounded to 1,000 imported catalog photos / 32 MB, saved atomically after
each photo, and removable from Library Analysis. It contains labels/OCR/face counts and optional text vectors.
It does not scan the user's entire Photos library, perform face identity matching or run a joint image-text model.


## Bundled sky and individual skin masks — 2026-10-20

- Sky: [Twist Labs SkySegSmall](https://huggingface.co/twistlabs/fotometis-sky/tree/97dfe50bf3fe4dc02badea287512afaf4ce857c2),
  based on xiongzhu666's MIT sky model. Pinned package files, exact sizes and SHA-256 values
  live in `scripts/build-mask-models.py`. Input is 384×384 RGB; output is a float16 sky
  probability image. No image-relative normalization is applied. Fine buildings/clouds may be misclassified.
- Skin: Google's Apache-2.0 MediaPipe Selfie Multiclass weights, from
  [senty-au's ONNX conversion](https://huggingface.co/senty-au/selfie_multiclass_256x256-ONNX/tree/6db8421a7150ac20558f2c24675078eb3a1a04d0).
  Source ONNX: 16,454,560 bytes, SHA-256
  `35ec1ecd9ee7f85073c99c00020b7f6751b69506eeacf683bc8665f6117f85b0`.
  Build script converts to Core ML FP32 with pinned conversion dependencies. Input is
  NHWC `[1,256,256,3]` RGB in `[0,1]`; output is six **logits**, followed by stable softmax
  in the app. Classes 2 (body skin) and 3 (face skin) are summed.
- Apple's Vision person-instance request creates independent silhouettes. People are numbered
  left to right. Skin inference crops each silhouette with context and intersects the mapped
  skin probabilities with that person's coverage. Limit: 20 detected people per request.
- Masks are saved as 256×256 normalized coverage through the existing engine command, included
  in undo/export/Photos settings. Skin quality for distant/occluded people remains unqualified;
  this portrait model is not guaranteed to segment every person in a crowd.
- Packages are compiled into each app; there is no runtime download or upload for sky/skin.
  Licenses/notices ship in the app. See `assets/ATTRIBUTION.md`.
- Conversion sanity check on one deterministic synthetic tensor: FP32 Core ML vs source ONNX
  maximum logit error 0.00009594, mean 0.00000459, identical argmax labels. This is a conversion
  check, not real-image mask-quality validation. The initial FP16 conversion was replaced by FP32.
