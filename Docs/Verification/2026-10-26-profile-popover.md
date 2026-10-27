# Profile popover from Edit

Updated 2026-10-26 from the user's request.

Edit's current Profile button now presents the existing grouped Profile chooser
in an anchored popover while preserving the Edit panel underneath. Tapping
outside dismisses the popover and returns to Edit. The current profile name and
Edit controls reload on dismissal. Profile selection and Amount use the existing
engine workflow; dismissal preserves applied changes.

The popover uses the dock-style header and does not allocate a second photo
preview. It retains the existing protection against dismissal during an active
profile operation or slider drag. Compact layouts also retain popover presentation.

No simulator or automated tests were run, as requested. Manual acceptance:
open Edit, tap the current Profile, browse/select a profile, tap outside, and
confirm Edit remains visible with the updated profile name and edited photo.
Build, signing and install evidence is in `LocalVerification/profile-popover-*`.

Delivery: Debug iOS device build and strict code-sign verification passed.
`devicectl` confirmed an in-place installation on the physical iPad using the
existing `com.cwallyman.UnveilNative` development identity. The app was not
uninstalled or launched. Visual and interaction behavior awaits user testing.
