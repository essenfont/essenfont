# 03 — MetricsPass: per-face vertical-metric recompute

## Problem

After stitching, each TTC face inherits vertical metrics from one of
its donors (whichever fontisan's Stitcher picks as the base). The
inherited metrics are frozen at Latin profile (`hhea.ascent=800,
descent=-200`) regardless of the face's actual glyph extents.

Face 8 (SMP) in v0.2.8 has `head.yMax=11160` but `OS/2.sTypoAscender=800`.
Renderers that trust OS/2 (Chrome, Windows) clip at ±800, cutting off
Tangut, Egyptian Hieroglyphs, and other tall glyphs.

## Constraint: fontisan tables are read-only

`Fontisan::Tables::HeadTable`, `HheaTable`, `OS2Table` have
`attr_reader` only — no setters. We cannot mutate table objects
in-memory after the Stitcher creates them.

## Solution: post-write binary patch

MetricsPass operates on the **TTC file** after `Stitcher#write_collection`
writes it to disk. It:

1. Opens the TTC in binary mode
2. Parses the TTC header to find each face's sfnt offset
3. Per face, parses the sfnt table directory to find `head`, `hhea`,
   `OS/2`, `glyf`, `loca` table offsets
4. Walks every glyph in `glyf` (via `loca` index) to compute the
   actual bbox union
5. Patches `head.xMin/yMin/xMax/yMax` at byte offsets 36-43
6. Patches `hhea.ascent/descent/lineGap` at byte offsets 4-9
7. Patches `OS/2.sTypoAscender/Descender/LineGap` at 68-73,
   `usWinAscent/usWinDescent` at 74-77
8. Writes the patched file

## API

```ruby
module Essenfont
  module Otc
    class MetricsPass
      DEFAULT_LINE_GAP = 0
      WIN_METRIC_CAP   = 0xFFFF

      attr_reader :ttc_path

      def initialize(ttc_path)
        @ttc_path = ttc_path
      end

      # Recompute head.bbox + hhea + OS/2 per face from actual glyphs.
      # @return [void] patches the file in-place
      def recompute!; end

      def self.recompute!(ttc_path)
        new(ttc_path).recompute!
      end
    end
  end
end
```

## Internal architecture (MECE)

```
MetricsPass              ← orchestrator: open file, iterate faces, save
├── FaceHeaderParser     ← parses TTC + sfnt headers → face table offsets
├── GlyphExtentsScanner  ← walks glyf/loca → bbox union per face
├── HeadTablePatcher     ← patches head.xMin/yMin/xMax/yMax (offsets 36-43)
├── HheaTablePatcher     ← patches hhea.ascent/descent/lineGap (offsets 4-9)
└── Os2TablePatcher      ← patches OS/2 sTypo + usWin (offsets 68-77)
```

Each table patcher is a standalone class with `call(file_data, offset, values)`.
OCP: adding a new table to patch (e.g., vhea for vertical metrics) = new class.

## Vertical metrics strategy

Per-face metrics computed from **actual glyph extents** (user's
confirmed choice: option "a"):

- `head.xMin/yMin/xMax/yMax` = exact bbox union across all glyphs
- `hhea.ascent` = `[yMax.abs, ASCENT_FLOOR].max` (at least 800, grow if needed)
- `hhea.descent` = `[yMin, DESCENT_CEILING].min` (at most -200, grow if needed)
- `OS/2.sTypoAscender` = `hhea.ascent` (keep in sync)
- `OS/2.sTypoDescender` = `hhea.descent`
- `OS/2.sTypoLineGap` = 0
- `OS/2.usWinAscent` = `[hhea.ascent, WIN_METRIC_CAP].min`
- `OS/2.usWinDescent` = `[hhea.descent.abs, WIN_METRIC_CAP].min`

ASCENT_FLOOR = 800, DESCENT_CEILING = -200 (Latin profile minimums).
Tall faces (Tangut, Egyptian) grow past the floor; Latin faces stay tight.

## head.modified timestamp

After patching head, also update `head.modified` (LONGDATETIME at
offset 28, 8 bytes). Format: seconds since 1904-01-01 UTC. This
avoids Chrome's OTS rejection window (if `modified` is too old or
zero, OTS can flag the font).

## Acceptance criteria

- [ ] Face 8 (SMP) `head.yMax` ≤ actual max glyph yMax + small margin
- [ ] Every face's `hhea.ascent ≥ 800`
- [ ] Every face's `OS/2.usWinAscent ≥ hhea.ascent`
- [ ] No face has `head.yMax > 1200` (after UPM normalization, glyphs fit in ~1000-upm)
- [ ] `head.modified` is non-zero and within the last hour
- [ ] TTC round-trips through Fontisan::Collection::Reader without errors
