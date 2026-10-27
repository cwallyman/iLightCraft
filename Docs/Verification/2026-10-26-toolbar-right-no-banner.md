# Trailing toolbar tools and no bottom status banner

Updated from the user's annotated iPad screenshot on 2026-10-26.

The Presets-through-Info tool group aligns to the right beside More when space
allows. Back, name, zoom and Export remain on the left. Narrow layouts retain
horizontal scrolling and their existing initial tool order.

Removed the passive bottom Photos status banner, including the repeated saved
confirmation that covered the photo controls. In-progress save feedback and
error/conflict handling remain. No simulator or automated tests run.
Device build/sign/install evidence: LocalVerification/toolbar-right-no-banner-*.

Delivery: device build and strict signature verification passed. The first
install attempt timed out; the retry succeeded. The app was not launched.
