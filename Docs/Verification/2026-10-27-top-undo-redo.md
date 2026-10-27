# Top-bar Undo and Redo — 2026-10-27

- Undo and Redo are visible immediately before More on both phone and tablet, with 44-point tap targets, labels, hover help and stable accessibility identifiers.
- Existing edit-history dispatch, Cmd-Z / Cmd-Shift-Z and disabled-state rules are retained. Removed the redundant hidden shortcut buttons and More-menu duplicates.
- No simulator or automated tests run. Physical visual/interaction acceptance remains with the user.
- Generic iOS build and strict signature verification passed; installs succeeded on iPad (sequence 2764) and iPhone (sequence 3936). Logs: LocalVerification/top-undo-redo-*.
