# Architecture

## Core idea
Split the app into a UI-free **engine** and a thin **app**. The engine knows how to do everything; the Mac UI is just one client of it. A future remote server for a phone app would be a second client of the same engine. That is what makes the remote feature possible later without a rewrite.

```
Gallra.app (SwiftUI views only)        [future] GallraRemote server (HTTPS, same Mac)
            \                                   /
             -------- GallraCore (Swift package) --------
             Catalog | Previews | Ratings | Moves | Similarity
```

## GallraCore modules (each exposed as a Swift protocol so UI and tests don't depend on the implementation)
| Module | Job |
|---|---|
| `FolderBrowser` | List folders/files, favorites, watch for changes |
| `Catalog` | Local SQLite cache (in `~/Library/Application Support/Gallra`): file list, ratings, thumbnails index, scene groups. It is a cache; RAW files remain the source of truth |
| `PreviewService` | Fast previews: extract the embedded JPEG from the RAW (CR3/3FR) via ImageIO or a small container parser; decode off the main thread; disk + memory cache; prefetch neighbours |
| `RatingService` / `RatingWriter` | Read rating; write rating into file safely (atomic, verified, backup) |
| `RejectService` | Move files to `Gallra Rejected` inside source folder; undo log; never delete |
| `SimilarityService` | Vision feature prints on previews + capture-time proximity, cluster into scenes |
| `Models` | `Photo`, `Rating`, `Scene`, `Tab`... plain data types, all `Codable` and `Sendable` |

## Rules that keep the remote option open
- Every action is a plain function on a service taking IDs/URLs and returning `Codable` data. No service knows about views.
- Photos are identified by stable IDs (path + volume + file ID), not by view state.
- Previews are served as ready-made JPEG data of chosen size, so the same call works locally or over a network.
- App state (tabs, filters) lives in observable view models, separate from services.
- Nothing in the engine uses AppKit/SwiftUI.

## App (SwiftUI)
- `Sidebar` (library, favorites) | `Tabs` | `Grid` (thumbnails + filter bar) | `Viewer` (single) | `Compare` (two panes sharing one zoom/pan state object, in normalized 0-1 coordinates so different resolutions line up)
- Zoom/pan view built with AppKit (`NSScrollView`/Core Animation) hosted in SwiftUI if SwiftUI gestures are not smooth enough.

## Distribution
- Build in Xcode; ad-hoc signed. Not notarized (needs a paid Apple account), so first launch on each Mac needs right-click > Open (or removing the quarantine flag). Sparkle handles updates, signed with its own free key pair (not Apple's). Sparkle-downloaded updates do not trigger the Gatekeeper warning again.
- Hosting for update files: GitHub Releases + an `appcast.xml` (free).
- Offline: the update check fails silently; nothing else needs the network.
