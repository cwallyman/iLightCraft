# Optional on-device models

Last updated: 2026-10-20. Models are not bundled, committed or downloaded automatically.
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

Depth package `DepthAnythingV2SmallF16.mlpackage`:

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

Depth inference uses a reduced current render and produces normalized relative depth, not metric distance.
Focus, range and blur strength produce a separate full-resolution half-float linear TIFF. It is a rendered
copy; depth/blur parameters are not an editable layer on the new photo. Bokeh shapes and painted depth
refinement remain future work. A normal 2D blur is not represented as a completed depth-model result.

Memory guards reject jobs exceeding estimated headroom and fail closed if available memory is unknown.
They are conservative estimates, not guarantees against every OS memory limit.
The private local analysis index is bounded to 1,000 imported catalog photos / 32 MB, saved atomically after
each photo, and removable from Library Analysis. It contains labels/OCR/face counts and optional text vectors.
It does not scan the user's entire Photos library, perform face identity matching or run a joint image-text model.
