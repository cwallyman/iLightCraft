# Settings and preset menu cleanup

Removed Presets & Batch Editing from the editor's main More menu. Batch Editing
is accessible from the Presets panel's own options menu instead.

Removed the static backup/recovery, CloudKit and layout explanation paragraphs
from Settings. Section titles, controls, licenses link and operational
progress/error messages remain.

No simulator or automated tests run. Device build/sign/install logs are under
LocalVerification/settings-cleanup-*. The universal iOS build targets iPad and
iPhone; the existing signing profile includes both physical devices.

Delivery: device build, whitespace check and strict signing verification passed.
`devicectl` confirmed installation on the physical iPad and iPhone 17 Pro,
sequences 2740 and 3912 respectively. Neither app was launched.

Follow-up: removed the Debug-only DiagnosticsMenuItems entry from the main More
menu. Diagnostics implementation remains internal. Delivery logs use
LocalVerification/no-diagnostics-menu-*. No simulator or automated tests run.
