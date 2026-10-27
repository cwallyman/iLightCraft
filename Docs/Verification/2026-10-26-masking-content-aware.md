# LightCraft masking tiles and Content-Aware

Updated 2026-10-26 from the user's screenshot and the parent LightCraft masking
panel source. Physical visual and behavior acceptance remains with the user.

Masking now uses a four-column grid of icon tiles: Subject, Sky, Background,
Brush, Linear, Radial, Luminance, Color, Each Person, Each Person's Skin,
Content-Aware and Object. Person and skin tiles call the existing local selection
implementation and create independent numbered masks. All People remains in the
three-dot menu. Tile labels and selected-mask controls retain the shared theme.

The panel includes selectable mask rows, overlay visibility, individual mask
visibility, overlay mode/color/opacity, Show Pins, component options and
Add/Subtract/Intersect/Invert/Delete actions. Overlay settings affect only the
preview, not saved develop settings. Pins use a component anchor or the centroid
of its stored foreground coverage; range selections may have no spatial pin.
Mask adjustment sliders now expose tone/detail directly, with Exposure at 0.01.

Content-Aware is enabled in Remove and as a tile within Masking. In Masking,
choose the tile, paint a stroke on the main photo and Apply Content-Aware. It
saves the same non-destructive `fill` spot type as Remove's Content-Aware mode.
It rebuilds the painted region from surrounding patches rather than aliasing
the older single-source Remove/Heal algorithm. Existing masks and originals are
preserved. Source selection/refresh is disabled for Fill because no single source
patch is used. Selecting a mask row or New Mask exits the fill interaction.

The retained engine received a focused backport of LightCraft's pure-Rust
`lightcraft-inpaint`, Fill enum/pipeline handling and bounded spot-radius fixes.
No general engine upgrade was performed. Provenance is in Engine/CHANGES.md,
Engine/NOTICE and the bundled ThirdPartyNotices. Upstream synthetic fill and
hostile-input regression cases remain in the sources. No tests, benchmarks or
simulators were run; the user will test manually.

Release engine builds passed for physical iOS and Mac Catalyst. Their local
XCFramework slices were updated; the simulator slice was intentionally not
built and must be rebuilt before future simulator work. Debug iOS device build
and whitespace checks passed. The device library hash matches the Xcode copied
library, and the app's linked binary contains PatchMatch complete/membrane
symbols. Logs and link evidence are under `LocalVerification/masking-fill-*`.

Manual acceptance: create Subject and per-person/skin masks, toggle/select rows,
change overlay modes/colors/opacity and Show Pins, add/subtract a manual
component, adjust/reset mask sliders, then paint/apply Content-Aware from both
menus. Check undo, saved repairs and export on a disposable photo.

Delivery: the final Debug iOS build and strict code-sign verification passed.
`devicectl` confirmed an in-place installation on the physical iPad under the
existing development app identity, sequence 2668. The app was not uninstalled
or launched. Device interaction, visual fit and fill quality await user testing.
