# LightCraft native icon catalog

The native UI uses LightCraft's original vector geometry from
`crates/ui-egui/src/icons.rs`, recorded verbatim in `lightcraft-icons.rs`.
`source.json` records its SHA-256. The original attribution and MIT/Apache-2.0
licenses are retained in the repository's asset attribution and this directory.

Regenerate with Python 3 + reportlab and Rust installed:

```sh
python3 scripts/generate-lightcraft-icons.py
python3 scripts/tests/test_lightcraft_icons.py
```

The recorder runs the original Rust painting functions without building the
engine. PDF assets retain their paths at every display scale and use template
tinting. `Contents.json` enables vector preservation. No SF Symbol fallback is
used. Native-only tools use the closest semantic LightCraft icon: analysis uses
Search, merge uses Stack, Lens Blur uses Radial, enhancement uses GradeHighlights,
HSL uses Sliders and optics uses Target. Redo and Rotate Right use a mirrored
Rotate; clipping indicators use an original geometric triangle.

Apple's system-owned Files and share sheets continue using their system UI.
The separately branded iLightCraft app/home lynx artwork is retained.
