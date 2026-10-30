# Gallra: Design

Status: updated with owner decisions (see end). Awaiting final approval.

## Direction
Dark, quiet, photo-first. The UI recedes so the photo is the brightest thing on screen. Inspired by Apple Aperture and Photoculler. One accent color, system font, no decoration. No pure black or pure white anywhere.

## Color tokens
Layered warm grays, matched by eye to the Claude desktop app's dark mode (values are approximations; adjust once seen on screen). The deeper the layer, the closer to the photo. Accent stays blue (owner-approved).

| Token | Hex | Use |
|---|---|---|
| `bg.window` | `#262624` | Window background, tab bar |
| `bg.sidebar` | `#30302E` | Sidebar |
| `bg.canvas` | `#1F1E1D` | Behind photos (grid, viewer, compare) |
| `bg.raised` | `#3A3A37` | Popovers, toolbars, filter bar |
| `bg.hover` | `#444441` | Hover and selected row |
| `line` | `#4A4A46` | 1 px dividers |
| `text.primary` | `#ECEBE6` | Main text |
| `text.secondary` | `#A3A29B` | Labels, metadata |
| `text.disabled` | `#6B6A65` | Disabled |
| `accent` | `#4C8DFF` | Selection ring, focus, active tab marker |
| `star` | `#F2C14E` | Filled stars |
| `reject` | `#E5645A` | Move-to-Rejected, destructive-looking actions |

Photo canvas is the darkest layer so images stand out. Contrast of `text.primary` on every background must be at least 7:1; `text.secondary` at least 4.5:1.

## Type
System font (SF Pro). Sizes in pt:

| Role | Size / weight |
|---|---|
| Section title | 13 / semibold |
| Body, sidebar items | 13 / regular |
| Metadata, badges | 11 / regular |
| Large overlay (filename in viewer) | 15 / medium |

Monospaced digits for counts, EXIF values and zoom percent.

## Spacing and shape
- Spacing scale: 4, 8, 12, 16, 24, 32.
- Corner radius: 6 (controls), 4 (thumbnails), 10 (popovers and dialogs).
- Thumbnail gap: 4 by default. Selection = 2 px accent ring, no fill.
- Motion: 120 ms ease-out for hover and selection; none for photo changes (instant).

## Window layout
```
+-----------------------------------------------------------+
| Tab: Folder A | Tab: Folder B | +                         |  tab bar
+----------+------------------------------------------------+
| Library  | Filter bar: [Any][1*][2*][3*][None]  Group  [-o--] |  toolbar
|  Folders |------------------------------------------------|
|  Favs    |                                                |
|  ...     |            content (grid / viewer / compare)   |
|          |                                                |
+----------+------------------------------------------------+
| 248 photos · 12 selected · /Volumes/Shoot/2026-10-12       |  status bar
+-----------------------------------------------------------+
```
Sidebar is collapsible (Cmd+Ctrl+S). On large monitors the content area grows; sidebar is 10% of the window width (minimum 140 pt), and the grid adds columns instead of enlarging thumbnails.

## Screens

### 1. Grid
- Thumbnails on `bg.canvas`, aspect ratio preserved, square cells, photo centered.
- Each thumbnail shows, on hover or when selected: star badge bottom-left (1-3 filled stars) and filename bottom (11 pt, on a soft gradient).
- Rated photos always show their stars faintly; unrated show nothing.
- Magnify slider in the toolbar (right): range roughly 80-400 pt cell size. Cmd+scroll or pinch also changes it.
- Rejected-pending photos are not shown (they are moved out of the folder).
- Filter bar: Any stars, 1, 2, 3, No stars, plus the "Move unrated to Rejected" button (see Cull actions). Active filter is highlighted with `accent`.
- Single click selects; double click or Space opens the viewer.

### 2. Viewer
- Photo fills the content area on `bg.canvas`, fit-to-window by default; click or Z toggles 100%; scroll to pan when zoomed.
- Minimal overlay, fades after 2 s of no mouse movement: filename (top-left), star control (top-right), position "37 / 248" (bottom-center).
- Optional EXIF strip (I key): camera, lens, ISO, aperture, shutter, focal length in `text.secondary`.
- Left/right arrow = previous/next, instant when cached (<50 ms target).
- Filmstrip along the bottom, on by default, 64 pt tall (F key hides/shows it). The current photo is highlighted with a 2 px `accent` ring, full brightness, while the other thumbnails are slightly dimmed (about 70% opacity). The strip auto-scrolls to keep the current photo centered. Click a thumbnail to jump to it.
- Esc returns to grid.

### 3. Compare
- Two panes side by side separated by a 1 px `line`, each with filename and stars on top.
- Zoom and pan are linked: same relative position and scale in both. Hold Option to move one pane independently; releasing re-links at the current offset.
- Active pane has a thin accent top border; rating keys apply to the active pane. Tab switches the active pane.
- Zoom percent shown bottom-center. Esc exits.

### 4. Scene groups
- Toggling Group inserts a thin header row per group: "Scene · 5 photos · 14:32", collapsible.
- Within a group photos stay in time order. The best-rated photo of the group gets a small marker in the header.
- Groups never reorder files on disk; this is a view only.

### 5. Cull actions
- Rating: keys 1, 2, 3, 0 to clear. Stars update instantly; the file write is background and a tiny spinner appears on the badge until it is verified. A failed write shows `reject`-colored badge and a message.
- Reject: key X moves the photo to the `Gallra Rejected` folder in the source folder. A toast at the bottom: "Moved 1 photo to Rejected · Undo (Cmd+Z)" for 8 s.
- Move all unrated: a button in the filter bar, enabled for the current filter. Opens a dialog: "Move 63 unrated photos to Gallra Rejected? Nothing is deleted. You can undo." Buttons: Cancel, Move (default is Cancel). Followed by the same undo toast.
- Files with no rating field count as unrated.

## Sidebar
- Sections: Favorites (top), Locations (Mac, external volumes), Folders (tree).
- Folder row: disclosure arrow, folder icon, name, photo count in `text.secondary`.
- Star icon on hover toggles favorite. Double-click or Cmd+click opens the folder in a new tab.

## Keyboard summary
| Key | Action |
|---|---|
| Arrows | Move selection / previous-next in viewer |
| Space / Return | Open viewer |
| Esc | Back to grid / exit compare |
| 1 2 3 / 0 | Set / clear rating |
| X | Move to Rejected |
| C | Compare selected two |
| Z | Toggle 100% zoom |
| I | Toggle EXIF strip |
| F | Toggle filmstrip |
| G | Toggle scene grouping |
| Cmd+Z | Undo last move or rating |
| Cmd+T / Cmd+W | New / close tab |

## States
- **Empty folder:** centered `text.secondary` message "No supported photos in this folder."
- **Loading:** thumbnails appear as gray placeholders (`bg.raised`) and fill in; never block scrolling.
- **Error (unreadable file):** placeholder with a small warning icon and filename.
- **First launch:** one-screen explanation of ad-hoc signing and how to open the app, then folder picker.

## Accessibility
- Every control reachable by keyboard; visible focus ring in `accent`.
- Never use color alone: stars have shape, rejects have text.
- Respects macOS "Reduce motion" and text size where practical.

## Decisions (owner)
- Accent is blue.
- Palette follows the Claude desktop app dark mode (warm grays).
- Reject key is X only.
- Viewer filmstrip is on by default, current photo highlighted.
