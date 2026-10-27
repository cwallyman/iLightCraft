# Menu scrolling space

Updated 2026-10-26 from the user's request.

Added a shared 32-point trailing content margin to editor panel scroll views,
lists and forms. This leaves blank space inside the scrollable area, so a finger
can scroll beside sliders, toggles and rows. The scroll indicator stays at the
panel edge. Existing content padding remains in addition to this margin.

The shared style covers Edit and the docked menus, including the Profile
popover. Standalone editor tool presentations use the same margin. System-owned
context menus and pickers retain their native layout.

No simulator or automated tests were run, as requested. Manual acceptance:
scroll a long Edit section, Presets, Profiles and Info from the right-hand blank
area, checking that values are not changed by the scrolling gesture.
Build/sign/install evidence is in `LocalVerification/menu-scroll-gutter-*`.

Delivery: Debug iOS device build, whitespace check and strict code-sign
verification passed. `devicectl` confirmed an in-place installation on the
physical iPad using the existing development app identity. The app was not
uninstalled or launched; gesture and visual acceptance remain with the user.

Follow-up: the shared Edit section header gives each visibility eye a 44-by-44
point touch target and 20 points of trailing separation from the disclosure
arrow. Applies to Light, Color, Effects, Detail, Optics and Calibration.
Evidence for this follow-up is in `LocalVerification/section-eye-spacing-*`.
No simulator or automated tests were run; manual checking should confirm that
eye taps change visibility while arrow taps only expand or collapse the section.
The follow-up device build and strict signature verification passed, and
`devicectl` confirmed the in-place iPad install. The app was not launched.
