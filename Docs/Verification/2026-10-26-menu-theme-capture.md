# Shared menu theme and histogram capture row

Updated 2026-10-26 from the user's request.

All editor tool presentations now apply Edit's Charcoal background, label and
text colors, typography and control tint at the shared presentation boundary.
The former native Form/List menus (Crop, Export, Info, Keywords, Red Eye,
standalone photo info, preset creation and editor settings/backup) use a shared
flat scrolling column and section headers/dividers. Navigation sheets also use
the dark panel toolbar colors. Preset rows use the same body/section font sizes.
The right scrolling gutter and existing slider theme remain in place.

The histogram always reserves a capture row in this order: ISO, focal length,
aperture and shutter speed. Missing fields display a dash individually rather
than hiding the row. The row has an accessibility identifier and combined label.

The editor first uses available catalog metadata, then fills missing/invalid
values using ImageIO metadata from the preserved original for Apple-decoded RAW
or HDR copies. The existing provenance sidecar resolves that original beside the
editing copy, with a basename-only path check. Metadata reads run off the main
actor on photo open, never decode image pixels, and never modify an original,
editing copy or catalog. No capture values are invented for files lacking EXIF.

A synthetic display/fallback regression case was saved in HistogramTests.swift.
No simulator or automated tests were run, as requested. Device build, signing
and install evidence is recorded under `LocalVerification/theme-capture-*`.
Manual acceptance remains with the user: inspect the row on an original RAW/HDR
photo and a metadata-free image, then compare Crop, Info, Keywords, Export,
Presets and Settings against Edit's colors, spacing and scrolling behavior.

Delivery: final Debug iOS build, whitespace check and strict code-sign
verification passed. `devicectl` confirmed installation on the physical iPad
under the existing development identity, sequence 2660. The app was not
uninstalled or launched. Visual and real-photo acceptance remains with the user.
