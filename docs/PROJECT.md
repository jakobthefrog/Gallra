# Gallra: Project Description

A native Mac app for fast, stable photo culling. Clean, uncluttered, inspired by Photoculler (https://photoculler.com/) and Apple Aperture. Few features, done very well. No editing of RAW files.

## Target
- Hardware: M5 MacBook Pro 16" and M5 MacBook Air (Apple Silicon), plus external larger monitors.
- Files: Canon EOS R5 (`.CR3`), Hasselblad X2D II (`.3FR`), plus `.DNG`, `.JPG`/`.JPEG`, `.TIF`/`.TIFF` (8/16 bit). Ratings go into the file: edited in place when the file already has a rating field; otherwise ImageIO copies the file with the rating added (JPEG/TIFF, no pixel re-encoding; DNG uses the blank padding inside its XMP block so the file size stays identical), verified with a backup. Also listed, previewed and filtered: HEIC/HEIF, ARW, NEF, RAF, CR2, ORF, RW2. Rating writes work for CR3, 3FR, DNG, JPG, TIFF and RAF (tested); the rest are never written to until tested on real files. The code must not hard-wire the list.
- Works fully offline. Checks for updates over the internet when available.
- Not on the App Store. No Apple Developer account.

## Features
1. Instant previews of large RAW files
2. Star rating (1-3 stars) of RAW files
3. Move unwanted RAW files into a folder inside the source folder (e.g. `Gallra Rejected`) so the user deletes them outside the app. Never delete from within the app. Also offer a one-step "move all unrated (no stars) files" action on the current filter, into the same folder, with undo.
4. Write star grades into the RAW file itself (no sidecar). See "Rating write notes" below.
5. Library sidebar to browse all local folders on the Mac
6. Mark folders as favorites
7. Open a folder as a tab; multiple tabs with different folders at once
8. Adjustable thumbnail size (magnify)
9. Compare two RAW files side by side with linked zoom and pan (same relative location, same rate and direction), to inspect identical crop areas
10. Filter by rating: 1, 2, 3 stars; no stars; any stars
    - Also filter by camera info (read-only EXIF): aperture, shutter speed, ISO and focal length, each as an exact value or a from/to range. Filters combine.
11. Group by similar scenes (visual similarity), so related shots stay together

## System rules
- No importing. Files are read where they are.
- No editing or tampering with files except writing the star rating and moving rejects.
- Architecture must allow a future iPhone/Android remote-control companion (not built now). See ARCHITECTURE.md.

## Design
- Dark theme in the spirit of Apple dark mode. No pure black (#000) or pure white (#FFF); use layered grays.
- Responsive layout that scales nicely to large monitors.
- Final visual style to be decided with Claude Design (Stage 1). Record decisions in `docs/DESIGN.md` once made.

## Rating write notes (to be confirmed in the Stage 0 spike on real files)
Writing a rating into a RAW file means changing the original file's bytes. Expected consequences:
- The file's modified date changes; its checksum changes (matters for backup verification tools and cloud sync, which will re-upload 50-200 MB files).
- Ratings are stored as XMP metadata (`xmp:Rating`) inside the file. CR3 is a container format where the XMP block sits in a metadata box; 3FR is TIFF-based with an XMP tag. If the existing XMP block has spare room the rating can be changed in place; if not, the file may need to be rewritten, which is riskier.
- Other software (Lightroom, Capture One, Hasselblad Phocus, Finder) may or may not read the rating from inside the file. Must be tested per app.
- Image data (the actual photo) is never touched.
- Fallback if writing proves unsafe for a format: store ratings in Gallra's own database and offer an optional sidecar. Decision made at the end of Stage 0 by the owner.
