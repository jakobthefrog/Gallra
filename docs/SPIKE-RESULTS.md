# Stage 0 spike results

Tested on 20 CR3 (R5) and 11 3FR (X2D II) files, Apple Silicon Mac, Xcode 27.2.

## Spike A: embedded previews (ImageIO, read-only)
- ImageIO opens both formats and returns the embedded JPEG preview. No custom parser needed.
- 3FR: preview ~3888 px wide, ~30-40 ms (first file 170 ms, cold).
- CR3: preview 4000x2668, ~95-105 ms cold including JPEG decode; ~50 ms warm.
- Both are fine for the <50 ms target once cached + prefetched. Full RAW decode of 3FR is 450-900 ms, so never use it for browsing.
- Open/metadata read: 0.3-10 ms.

## Spike B: rating write (on scratch copies only)
- Both formats already contain an XMP packet with a one-digit rating: CR3 `<xmp:Rating>0</xmp:Rating>`, 3FR `<xap:Rating>0</xap:Rating>`.
- Changing the digit keeps the file size identical (no offsets move). Exactly 1 byte differs from the original; setting it back gives a byte-identical file.
- Write method tested: copy to temp file, change the digit, verify (same size, 1 byte differs, preview still decodes), atomic replace.
- ImageIO reads the new value back for both formats.
- NOT yet verified: do Finder, Lightroom and Phocus show the rating? Test files: `Gallra-TestPhotos/rating-test/` (both set to 3 stars).
- Caveat: only tested on files whose rating field already exists (all 31 samples). A file without the field needs a fallback (skip with a message, or sidecar `.xmp`).
