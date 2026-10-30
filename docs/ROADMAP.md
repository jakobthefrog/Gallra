# Roadmap

Rule: one stage per chat session. Finish, tick boxes, commit, then start a fresh session for the next stage.

## Stage 0: Setup and risk spike (do first)
- [ ] Install Xcode (App Store, free, ~10 GB). Open it once and accept the license.
- [ ] `git init` + first commit (safety net / undo for everything)
- [ ] Put 10-20 COPIES of sample files in `~/Documents/Gallra-TestPhotos/` (CR3 from R5, 3FR from X2D II, a few already rated). Never test on originals.
- [ ] Spike A: extract embedded preview from CR3 and 3FR, time it
- [ ] Spike B: read and write a rating inside a COPY of each format; verify image data unchanged; test that Finder/Lightroom/Phocus see it
- [ ] Decide: in-file writing OK per format? (owner decision, see PROJECT.md)
- [ ] Hello-world Xcode project + `GallraCore` package builds

## Stage 1: Design (Claude Design)
- [ ] Style direction, colors, type, spacing, key screens (grid, viewer, compare); save in `docs/DESIGN.md`

## Stage 2: Engine foundation
- [ ] Models, FolderBrowser, Catalog (SQLite), PreviewService with caching + prefetch, tests

## Stage 3: Core app shell
- [ ] Sidebar + favorites, tabs, thumbnail grid with magnify slider, single-photo viewer, keyboard navigation

## Stage 4: Cull actions
- [ ] Star rating (keys 1-3, 0 to clear), rating write, filters, move-to-Rejected with undo

## Stage 5: Compare
- [ ] Side-by-side with linked zoom and pan

## Stage 6: Scene grouping
- [ ] Vision feature prints + time clustering, group UI

## Stage 7: Polish and ship
- [ ] Performance pass on thousands of files, large-monitor layout, app icon
- [ ] Sparkle updates, release build, GitHub Releases, first-launch instructions for users

## Later (do not build yet)
- Remote companion server + mobile apps
