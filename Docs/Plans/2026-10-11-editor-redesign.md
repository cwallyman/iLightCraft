# Home and editor redesign: plan

Spec: `Docs/Specs/2026-10-11-editor-redesign-design.md`. Branch `elio/editor-redesign` (from `elio/editor-alpha-ui`
at `c18a80d`). Workers never commit; the coordinator commits each ticket and merges both branches into `main`
when R4 passes. Verifier: Opus high, runs checks itself. Ladder on FAIL as in the v0 plan.

| Ticket | Scope | Start rung |
|---|---|---|
| R1 | Home: background, floating cards, title, glass panel with Files/Photos, embedded Files browser (device spike first) and inline Photos picker; home ↔ editor navigation shell; purple AccentColor | Opus high |
| R2 | Editor chrome: top bar (back, title menu, Edited/Original, zoom pill), trailing actions (Undo/Redo placeholders, Share disabled, ellipsis with Reset All and Debug diagnostics), trailing tool rail (Move, Adjust); inspector removed; hosting tests rewritten | Sonnet high |
| R3 | Adjust card: carousel with bottom page strip, custom slider (centred fill, haptics, precision bands, value entry), steppers repeat as drafts | Opus high |
| R4 | Undo/Redo snapshot stacks wired to the toolbar, Reset All as one undoable edit | Sonnet medium |

Device for every ticket: iPad Air 11" M2, test destination `platform=iOS,id=00008112-0001189C3A46601E`,
devicectl id `86B6DAFF-CBC5-5272-9C2A-F9C07FC92F0B`.
