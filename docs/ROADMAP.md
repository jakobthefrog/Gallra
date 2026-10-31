# Roadmap

Rule: one stage per chat session. Finish, tick boxes, commit, then start a fresh session for the next stage.

## Stage 0: Setup and risk spike (do first)
- [x] Install Xcode (App Store, free, ~10 GB). Open it once and accept the license.
- [x] `git init` + first commit (safety net / undo for everything)
- [x] Put 10-20 COPIES of sample files in `~/Documents/Gallra-TestPhotos/` (CR3 from R5, 3FR from X2D II, a few already rated). Never test on originals.
- [x] Spike A: extract embedded preview from CR3 and 3FR, time it
- [x] Spike B: read and write a rating inside a COPY of each format; verify image data unchanged; test that Finder/Lightroom/Phocus see it
- [x] Decide: in-file writing OK per format? (owner decision, see PROJECT.md)
- [x] Hello-world Xcode project + `GallraCore` package builds

## Stage 1: Design (Claude Design)
- [x] Style direction, colors, type, spacing, key screens (grid, viewer, compare); save in `docs/DESIGN.md`

## Stage 2: Engine foundation
- [x] Models, FolderBrowser, Catalog (SQLite), PreviewService with caching + prefetch, tests

## Stage 3: Core app shell
- [x] Sidebar + favorites, tabs, thumbnail grid with magnify slider, single-photo viewer, keyboard navigation

## Stage 4: Cull actions
- [x] Star rating (keys 1-3, 0 to clear), rating write, filters, move-to-Rejected with undo, "move all unrated" action (files with no rating field count as unrated)

- [x] Camera-info filters (aperture, shutter, ISO, focal length; exact value or from/to) in a Filters popover; EXIF read in the background for the whole folder

## Stage 5: Compare
- [x] Side-by-side with linked zoom and pan

## Stage 6: Scene grouping
- [x] Vision feature prints + time clustering, group UI

## Stage 7: Polish and ship
- [x] Performance pass on thousands of files, large-monitor layout, app icon (scrolling feel and wide-window look still to check by hand)
- [x] Sparkle updates, release build, GitHub Releases (v1.0 published), first-launch instructions

## Stage 8: More file formats
- [x] JPG/JPEG, TIFF (8/16 bit) and DNG are listed, previewed and read (`PhotoFormat`)
- [x] Rating write for files without a rating field: safe ImageIO rewrite with backup + verify (`RatingRewriter`), tested on generated JPG/TIFF 8/16 bit
- [x] Tested on COPIES of real samples: camera JPG, 8-bit and 16-bit TIFF (ImageIO rewrite), Lightroom DNG (ImageIO cannot write DNG, so the rating goes into the XMP padding: same file size, nothing else moves)
- [ ] Decide on HEIC and other RAW types (ARW, NEF, RAF, CR2...)

## Later (do not build yet)
- Remote companion server + mobile apps
