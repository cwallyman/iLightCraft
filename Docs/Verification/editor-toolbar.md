# Editor toolbar — 2026-10-20

HDR Editing (sun), On-device Tools (sparkles), Crop & Rotate (crop/rotate),
Show Original (half-filled circle), and Reset All (counterclockwise arrow) now
appear beside Edit as icon controls on Mac and iPad. iPhone retains all five
inside More, including landscape. Shared controls preserve enabled states and
bindings; toolbar controls expose labels and hover help.

Verification: Mac Catalyst and universal iOS Debug builds passed. Updated Mac
app installed at /Applications/iLightCraft.app, signature verified, and launched.
The native app observation found an Open dialog, so the editor toolbar was not
visually verified. Physical iPad/iPhone installation and layout checks remain
pending. No full test suite or upstream CI run; no commit created.

## More menu / custom-view overflow correction — 2026-10-20

User's Mac capture showed an empty tiny popover below the system overflow ellipsis.
The separately hosted hover buttons were being moved into UIKit overflow as custom views.
Mac/iPad tools now occupy one bounded horizontal scrolling strip with its own hosting
boundary, while More is a separate native SwiftUI Menu, without the hover hosting wrapper.
Photo titles truncate at 180 points to reserve toolbar space. More always includes Info and
Fit Photo, plus Photos save when applicable and Debug diagnostics. iPhone retains its More
tool entries. Existing hover labels and selected-state styling remain on tool icons.

Mac Catalyst and universal iOS builds passed; signed updates installed on Mac/iPad after
backing up iPad Application Support. Read-only Mac accessibility and screenshots confirmed
all tool buttons, Export and the actual `more-menu` button instead of `OverflowBarButtonItem`.
An intermediate ScrollView implementation dropped icons and was corrected with an explicit
hosting boundary before final delivery. Active icon styling uses explicit brand amber across
that boundary. No synthetic clicks or automated suites/benchmarks run; opening More and
narrow-window scrolling remain hands-on acceptance checks.

### Latest iPhone delivery

The signed universal build including HSL, Profiles, active-tool styling and the More-menu
correction was installed successfully on the paired iPhone 17 Pro on 2026-10-20. Initial
inventory showed unavailable and the pre-update Application Support backup timed out; the
subsequent install reconnected successfully. Existing app data was not intentionally removed.
This is installation evidence, not a hands-on menu or editing test.
Automatic iPhone launch was denied by its lock screen. Unlock and open iLightCraft for
physical checks; installation itself succeeded.
