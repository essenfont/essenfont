# OTC Essenfont — Epic Overview

## Why this exists

essenfont's glyph count (~131,193 unique glyphs after dedup) exceeds the
TrueType `maxp.num_glyphs` uint16 cap of 65,535. Single-TTF output is
therefore impossible without dropping glyphs, and the current build
loses ~3,000 cmap entries to that cap (see
`/Users/mulgogi/src/fontist/fontisan/BUG-stitcher-gid-cap-65535.md`).

fontisan 0.4.6 confirmed in spec that **both TTF and OTF formats cap at
65,535 glyphs** in the current implementation. The fix is to ship
essenfont as an **OpenType Collection (OTC)** — one file, multiple
subfonts, each ≤65,535 glyphs.

## What we are building

A new `Essenfont::Otc` subsystem that:

1. Partitions the per-codepoint donor map into named subfonts, one per
   Unicode plane (BMP, SMP, SIP, TIP, SSP), with block-level sub-split
   for any plane that exceeds the cap.
2. Drives `Fontisan::Stitcher#write_collection(path, format:)` to emit
   a single `Essenfont-Regular.otc` containing all subfonts.
3. Plugs into the existing `scripts/build.rb` as the default output
   path when glyph count > 65,535. The single-TTF path remains as a
   fallback for users who want a per-plane TTF.
4. Distributes the `.otc` via `essenfont.github.io` as the canonical
   release artifact. Per-plane TTFs are also published for clients
   that cannot consume OTC.

## Decisions

### D1 — OTC over TTC

OTC is the format that supports both `glyf` (TrueType outlines) and
`CFF`/`CFF2` (PostScript outlines) subfonts. TTC restricts all
subfonts to TrueType. essenfont's donor mix is currently all TrueType
(Noto + FSung), so TTC would work today, but OTC leaves room for CFF
donors (e.g., a future NotoSerifTibetan OTF) without re-architecting.

**Output file extension:** `.otc`
**Format symbol passed to fontisan:** `:otc`

### D2 — Subfont format: TTF (glyf), not CFF

All current donors are TrueType (`glyf` table). CFF would require
re-outlining every donor glyph, with no fidelity benefit. Subfont
format symbol: `:ttf`. fontisan's `collection_format_for` will
translate to `:otc` automatically when given a non-`:ttf` collection.

Wait — looking at `collection_format_for`:

```ruby
def collection_format_for(subfont_format)
  subfont_format == :ttf ? :ttc : :otc
end
```

This is the inverse of what we want. We want `:otc` for everything
essenfont ships. **Action:** file a fontisan PR to decouple the
collection format from the subfont outline format, or use the
lower-level `Collection::Builder` API directly (see D5).

### D3 — Plane-based partition is the MECE default

Unicode planes are Mutually Exclusive (a codepoint lives in exactly
one plane) and Collectively Exhaustive (every codepoint is in some
plane). This is the natural partition axis:

| Plane | Range             | Name                          |
|-------|-------------------|-------------------------------|
| 0     | U+0000..U+FFFF    | BMP (Basic Multilingual)      |
| 1     | U+10000..U+1FFFF  | SMP (Supplementary Multilingual) |
| 2     | U+20000..U+2FFFF  | SIP (Supplementary Ideographic) |
| 3     | U+30000..U+3FFFF  | TIP (Tertiary Ideographic)    |
| 14    | U+E0000..U+EFFFF  | SSP (Supplementary Special-purpose) |

PUA-A (Plane 15) and PUA-B (Plane 16) are excluded — essenfont
filters them out of the donor manifest.

### D4 — Block sub-split when a plane exceeds the cap

Unicode 17 BMP has ~62,000 assigned codepoints (excluding surrogates
and non-characters), and SIP has ~60,000. Both fit under 65,534 (cap
minus .notdef). But future Unicode versions or donor-side dedup
misses could push a plane over. The partition strategy must
sub-split by block when needed.

Sub-split naming convention: `:plane_2_a`, `:plane_2_b`, etc., where
the suffix indicates the sub-split index within the plane.

### D5 — Use `Fontisan::Collection::Builder` directly

The `Stitcher#write_collection` helper hardcodes the collection
format from the subfont format (see D2). To keep TTF subfont outlines
*and* ship OTC, we drive the lower-level API:

1. For each partition: `stitcher.write_to(temp_path, format: :ttf, subfont: name)`
2. `Fontisan::FontLoader.load(temp_path)` to get a `TrueTypeFont`
3. Pass the list of loaded fonts to `Collection::Builder.new(fonts, format: :otc).build_to_file(output_path)`

This is more code but gives us full control over the collection
format. Alternative: extend `Stitcher#write_collection` with a
`collection_format:` keyword (fontisan PR).

### D6 — Subfont names are stable, semantic identifiers

Subfont names follow `<family>-<plane>`: `Essenfont-BMP`,
`Essenfont-SMP`, `Essenfont-SIP`, `Essenfont-TIP`, `Essenfont-SSP`.
The family name (`Essenfont`) and version (`1.0`) are identical
across subfonts. The PostScript name suffix disambiguates
(`Essenfont-BMP`, etc.) for font managers that index by PS name.

### D7 — Open/Closed: pluggable partitioner

`Essenfont::Otc::Partitioner` is an abstract interface.
`PlanePartitioner` is the default. A future user could supply a
custom partitioner (e.g., "by script family" or "by donor license")
without touching the build pipeline.

The build pipeline depends on the interface (`#partition(cp_map) →
Blueprint`), not the concrete class.

### D8 — Code quality rules (from global CLAUDE.md)

- **No `require_relative`** — use Ruby `autoload`, declared in the
  immediate parent namespace's file.
- **No `send` to call private methods** — if a private method needs
  to be reached, the API boundary is wrong.
- **No `instance_variable_set` / `instance_variable_get`** — add a
  public accessor or rethink ownership.
- **No `respond_to?`** — use `is_a?` or design the type hierarchy so
  the check isn't needed.
- **No hand-rolled serialization** — N/A here (no model persistence).
- **No doubles in specs** — use real `Struct` instances or real
  `Fontisan::Ufo::Glyph`/`Fontisan::Ufo::Font` objects.

## Documents in this epic

| # | File | Topic |
|---|------|-------|
| 00 | `00-README.md` | This overview. Decisions, scope, non-goals. |
| 01 | `01-otc-format-spec.md` | OTC binary structure, fontisan API used. |
| 02 | `02-plane-partition-strategy.md` | MECE plane partition + sub-split algorithm. |
| 03 | `03-subfont-budget.md` | 65,535 cap accounting, .notdef reservation, validation. |
| 04 | `04-architecture.md` | `lib/essenfont/otc/` class layout, autoload map, responsibilities. |
| 05 | `05-build-pipeline-integration.md` | Changes to `scripts/build.rb`. |
| 06 | `06-website-distribution.md` | essenfont.github.io changes + release flow. |

## Non-goals

- **Variable font support.** All donors are static. fvar/avar/MVAR
  dedup paths in `fontisan/collection/table_deduplicator.rb` are
  unused.
- **Per-script subfont granularity.** One subfont per plane is enough
  for the cap. Finer granularity (e.g., a Latin subfont vs CJK
  subfont within BMP) is over-engineering for the fallback-font use
  case.
- **WOFF2 packaging at the OTC level.** WOFF2 wraps single fonts;
  there is no spec for WOFF2 collections. Per-plane TTFs may be
  WOFF2'd for web use.
- **Replacement of the existing TTF path.** The single-TTF `build.rb`
  path stays as `--format=ttf` for per-plane testing and for any user
  who only wants the BMP. The default switches to OTC.

## Success criteria

1. `ruby scripts/build.rb` produces `Essenfont-Regular.otc` with no
   glyph drops and no cmap repair warnings.
2. The OTC contains 5 subfonts (BMP, SMP, SIP, TIP, SSP), each with
   `maxp.num_glyphs ≤ 65,535`.
3. `fc-query Essenfont-Regular.otc` reports 5 faces.
4. Coverage returns to ≥96% (no cap-induced drops).
5. `essenfont.github.io` offers the OTC for download, with per-plane
   TTF links alongside.
6. README documents the OTC as the canonical release artifact.
