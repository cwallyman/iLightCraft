# Yellow changed-control indicators

Updated 2026-10-26 from the user's request.

Changed adjustment labels, readouts and slider handles now use the same
AccentColor as selected presets (#F2A516). A changed handle fills yellow; the
unchanged handle remains hollow gray. Track gradients remain unchanged. Returning
to the control's default returns the label, value and handle to neutral.

Core adjustments compare with the open photo's actual import defaults, so RAW
sharpening and as-shot white balance are not marked changed merely for being
nonzero. Generic engine controls use their control specification defaults.
Relative Temp/Tint use the corresponding photo defaults after the same display
conversion. A small numeric tolerance avoids highlighting floating-point noise.

The shared slider row covers mask/manual/repair/overlay controls and preserves
their nonzero defaults (flow/density 100, repair feather 60, opacity 100,
overlay opacity 35, brush radius 0.025). Mask adjustments use neutral zero.
Preset/profile Amount uses 100. Crop, lens blur, merge, red-eye and curve point
controls use their relevant defaults. Editable profile, curve preset, crop,
white-balance, vignette, lens and repair-mode labels also indicate changed state.
Existing selected preset coloring and precision/accessibility gestures remain.

No simulator, automated tests or performance benchmarks were run. Verification
is the device build, whitespace check, signing and physical installation, with
logs under `LocalVerification/changed-highlights-*`. Manual acceptance: adjust
and reset controls in Edit, including an imported RAW's default Detail/WB;
apply a preset; adjust a mask, repair and profile/preset Amount; check yellow
labels/readouts/handles, and confirm neutral styling returns at the default.

Delivery: final Debug iOS build, whitespace check and strict code-sign
verification passed. `devicectl` confirmed an in-place installation on the
physical iPad under the existing development identity, sequence 2684. The app
was not uninstalled or launched. Visual and interaction acceptance remains with
the user.
