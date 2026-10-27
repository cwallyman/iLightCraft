# Selected preset Amount and Reset

Updated 2026-10-26 from the user's screenshot and request.

Selecting a preset shows a fixed Amount strip directly under the Presets header,
with a 0–200 slider and numeric readout, starting at 100. The grouped list remains
below it. Dragging updates the readout; release applies the selected amount.
VoiceOver amount adjustments also apply. Presets > More (…) now includes Reset.

Each selection captures the photo's settings before applying that preset. Amount
changes restore this full baseline before applying the preset at the new strength,
avoiding cumulative blends and preserving earlier edits. Full settings restore
also handles omitted default HDR fields and empty mask lists. Reset restores the
baseline, clears selection and hides Amount. Re-clicking the same selected preset
restores Amount 100 without losing its baseline. Updated later on 2026-10-26:
choosing a different preset now restores the same original baseline first, so
the previous selection is replaced rather than stacked. The selected state is
retained by the editor when the panel is closed/reopened. An intervening manual
edit still invalidates stale preset state rather than being silently discarded.

The model serializes restore/apply and creates a native undo snapshot. It checks
photo identity and the expected settings before modifying anything; an intervening
edit makes a stale adjustment/reset refuse instead of discarding that edit. Failed
preset application attempts recovery to the immediately preceding settings. The
selected Amount state is cleared when refreshed settings no longer match it.

`iLightCraftTests/PresetAmountTests.swift` contains a synthetic baseline/reset/
non-cumulative-amount/intervening-edit regression scenario. It is saved, not run,
per the user's instruction. No simulator was started and no automated tests were
executed. Build/sign/install evidence is recorded in LocalVerification. Physical
behavior and visual acceptance remain for the user.

Delivery: the final Debug iOS device build and strict code-sign verification
passed. `devicectl` confirmed App installed on the existing iPad identity
`com.cwallyman.UnveilNative`, without uninstalling or launching it. Evidence:
`LocalVerification/preset-amount-delivery-build.log`, `preset-amount-sign.log`
and `preset-amount-ipad-install.log` / `.json`. No simulator was used.
