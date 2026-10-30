# Gallra

Native macOS photo-culling app for fast, stable review of large RAW files (Canon EOS R5 `.CR3`, Hasselblad X2D II `.3FR`). No editing, no importing. Full spec: `docs/PROJECT.md`. Design of the code: `docs/ARCHITECTURE.md`. Build order: `docs/ROADMAP.md`.

## Working rules (read first)
- The owner is new to AI and coding. Explain decisions in plain language, briefly. Never dump long code into chat; write it to files.
- Owner is on a low-cost plan: keep answers short, read only the files you need, don't re-read files already in context, no subagents unless asked.
- Work on ONE roadmap stage at a time. Do not start the next stage or add features not in `docs/PROJECT.md`.
- Before coding a stage: state a short plan, wait for OK. After coding: build, run tests, say what was verified and what wasn't.
- Update the checkboxes in `docs/ROADMAP.md` when a task is done.

## Tech
- Swift 6, SwiftUI (AppKit only where SwiftUI falls short, e.g. zoom/pan view). Minimum macOS 15. Apple Silicon only.
- UI-free logic lives in the local Swift package `GallraCore/`. The app target only holds views. See architecture doc.
- Apple frameworks first (ImageIO, Vision, Metal, FileManager). Third-party only: Sparkle (updates). Ask before adding any other dependency.
- Distribution: no Apple Developer account. Ad-hoc signed, not notarized, updates via Sparkle.

## Hard safety rules for user files
- NEVER modify, rename, or delete a user's RAW file except (a) writing a star rating through `RatingWriter`, (b) moving it to the Rejected folder inside its source folder. No other writes. Never permanently delete.
- Rating writes must be safe: verify the file after writing, keep a recoverable backup until verified, and be atomic (temp file + replace). Test only on COPIES of sample files, never originals.
- All file operations go through `GallraCore` services, never directly from views.

## Conventions
- Small files, clear names, doc-comment each public type. Async/await for I/O; never block the main thread.
- Performance targets: next/previous photo shows a preview in <50 ms once cached; scrolling thousands of thumbnails stays smooth.
- Tests for anything touching files, ratings, or grouping (`GallraCore/Tests`).
