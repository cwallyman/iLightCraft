# Preset selection replaces the previous selection

Updated 2026-10-26 from the user's request.

Selecting preset B after preset A restores the settings from before A, then
applies B. This removes fields introduced only by A, including fields B does not
specify. Earlier edits remain in the baseline. Selection starts at Amount 100
when clicked; later Amount changes and Reset continue using that original
baseline. Clicking an already-selected preset at its current amount is a no-op.

The editor retains the guarded preset selection state across panel closure and
reopening for the same open photo. Opening a photo clears that temporary state.
Intervening manual changes invalidate the selection, preserving those changes
rather than overwriting them with a stale baseline. Existing serialized restore,
photo identity checks, rollback on failure and undo snapshots are unchanged.

Saved regression coverage switches from Vivid Pop to Cool Morning after reopening
the panel and checks that Vivid Pop's contrast/whites/blacks/clarity/saturation
are removed while earlier exposure/contrast edits remain. Reset restores the
original baseline. No simulator or automated tests were run, as requested.
Build/sign/install evidence is under `LocalVerification/preset-replacement-*`.

Delivery: Debug iOS device build, whitespace check and strict code-sign
verification passed. `devicectl` confirmed the in-place iPad installation under
the existing development identity, sequence 2676. The app was not uninstalled
or launched. Runtime behavior awaits user testing.
