# Before / Edited and phone toolbar — 2026-10-27

- Bottom view choices are Single Photo and Before / Edited. The latter shows the same photo in two labelled panes.
- The native comparison query renders the engine's selected before state (import defaults unless a custom before state is chosen) and current settings without changing the document. Both retain current crop/orientation. Preview long edge is capped at 1600 pixels; the app requests 1400.
- Commits, photo changes and tool-panel changes refresh comparison. Opening spatial tools returns to Single Photo. Numeric zoom targets both panes; touch pan/zoom is independent per pane.
- On iPhone all top action buttons are in More; the photo name remains visible. More uses a 26-point icon in a 48-point target on both iPhone and iPad.
- Error/retry UI takes precedence over an old comparison if rendering fails.
- Device and Mac Catalyst engine libraries built. The simulator slice was not rebuilt.
- Automated tests and simulators were not run, by request. Physical interaction and visual acceptance are left to the user.
- Universal iOS Debug build and strict code-signature verification passed. Device installs succeeded on Sniglefritz Sr. (iPad) and Sniglefritz (iPhone); local logs/JSON are in LocalVerification/before-after-phone-*.
- Saved BeforeEditedComparisonTests checks different before/edited pixels, matching bounded dimensions and unchanged photo settings/selection. It was not run.
