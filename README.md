# Gallra

Native macOS app for fast photo culling of large RAW files (Canon `.CR3`, Hasselblad `.3FR`). No editing, no importing: open a folder, rate with 1-3, press Delete to move rejects to a `Gallra Rejected` folder. Apple Silicon, macOS 15 or newer.

## Install
1. Download `Gallra-x.y.zip` from the [latest release](https://github.com/jakobthefrog/Gallra/releases/latest) and unzip it.
2. Drag `Gallra.app` to your Applications folder.
3. **First launch:** Gallra is not notarized by Apple, so macOS will say it can't be opened. On macOS 15 or newer:
   - Try to open it once and click **Done**, then open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Gallra; or
   - run `xattr -dr com.apple.quarantine /Applications/Gallra.app` in Terminal.

   You only need to do this once. After that, updates arrive inside the app (**Gallra → Check for Updates…**).

## What Gallra does to your files
Only two things, both on purpose: it writes a star rating into the RAW file's XMP rating field (verified after writing, with a backup kept until then), and it moves rejected photos into a `Gallra Rejected` folder inside the same folder. Nothing is ever deleted. Cmd+Z undoes a reject.

## Keys
Arrows move · Space/Return open viewer · Esc back · 1 2 3 / 0 rate / clear · Delete reject · C compare · Z 100% zoom · F filmstrip · G group scenes · Cmd+Z undo · Cmd+T / Cmd+W new / close tab.

See `docs/` for the full spec, design and architecture.
