# Grouped LightCraft presets

Updated 2026-10-26 at the user's request, using their screenshot as the layout reference.

The default Presets panel is now an indented, grouped list with expandable
headings, matching LightCraft's alphabetical group order and the engine's
original preset order inside each group. Groups start expanded. The header has
More and Create (+), with favorites and user-preset actions in context menus.
Creation/settings fields and batch controls no longer precede the shared list.
Native batch workflows remain accessible through the editor's More menu.

The retained engine already contains the **exact same built-in preset definitions**
as the desktop checkout. The `builtin()` source section matches byte-for-byte:
SHA-256 `78449cc1a2fcd494c55aceb778e1f4eb50393e8c0138b91d4deaeb901b17b716`.
No engine replacement, preset recreation or third-party assets were needed.
All 41 stock presets are loaded from `presets.list`, along with existing user presets.

| Group | Stock presets |
|---|---:|
| B&W | 4 |
| Color | 5 |
| Film | 3 |
| Food | 3 |
| Landscape | 8 |
| Portrait | 5 |
| Seasons | 4 |
| Style | 2 |
| Urban | 4 |
| Vintage | 3 |

The list retains stable preset IDs, applies through `preset.apply`, and preserves
favorites and existing user presets. Built-ins remain protected from update,
rename and deletion. Creation supports a user-selected group. The list supports
search/favorites filtering and expanding/collapsing all groups through More.

Validation: unsigned Debug iOS device build passed; strict signing verification
passed; `git diff --check` passed. No simulator or automated tests were run,
per the user's instruction to leave testing to them. Visual and physical behavior
acceptance is pending their review. Device install evidence is in
`LocalVerification/grouped-presets-ipad-install.log` and its JSON companion.
