# Essenfont Architecture

## What this repo builds

One OTC file (`Essenfont-Regular.otc`) containing 5 OpenType faces,
one per Unicode plane that carries assigned characters:

| Face | Plane  | Range             | Glyphs   | Notes                              |
|------|--------|-------------------|----------|------------------------------------|
| 0    | BMP    | U+0000–U+FFFF     | ~42,000  | World scripts (Latin, CJK, Arabic) |
| 1    | SMP    | U+10000–U+1FFFF   | ~21,000  | Historical, emoji, math, symbols   |
| 2    | SIP    | U+20000–U+2FFFF   | ~2,000   | CJK Unified Ideographs Ext B–I     |
| 3    | TIP    | U+30000–U+3FFFF   | ~15,000  | CJK Ext G–J, Tangut, Khitan        |
| 4    | SSP    | U+E0000–U+EFFFF   | ~1,500   | Language tags, variation selectors |

Each face is stitched from multiple OFL-licensed donor fonts,
converted to UFO and normalized to `unitsPerEm = 1000` before
stitching.

## Repository layout

```
lib/essenfont/             Ruby library — build logic
  essenfont.rb             Root namespace (autoload registry)
  donor.rb                 Donor::Info — typed loaded-donor value object
  cp_map.rb                Codepoint → donor mapping
  donor_loader.rb          Font loading + UFO conversion + normalization
  outline_policy.rb        CBDT detection (bypasses UFO path)
  ucode_ref.rb             Unicode block range lookups
  coverage_gate.rb         Build-time coverage validation
  manifest.rb              manifest.yml parser
  manifest/entry.rb        Single donor entry
  otc.rb                   Otc namespace (autoload)
  otc/build.rb             Build orchestrator (collection, per-plane, single-face)
  otc/metrics_pass.rb      Per-face vertical-metric recompute
  otc/naming.rb            Name table strings
  otc/errors.rb            Typed errors
  otc/version.rb           Version constant
  ufo.rb                   Ufo namespace (autoload)
  ufo/normalization.rb     Per-donor UPM scaling

sources/
  manifest.yml             Donor registry (single source of truth)
  remaps/                  Codepoint remap files

references/input-fonts/    Donor font binaries (gitignored, sha256-verified)

scripts/                   Build entry points
  build.rb                 Full build (--format=ttc / --format=ttf-per-plane)
  release.rb               Release packaging
  verify.rb                Post-build assertions

spec/                      RSpec test suite
docs/                      This directory
```

## Build pipeline (7 stages)

```
manifest.yml
     │
[1]  ▼  Manifest::Collection.parse
         │   Reads sources/manifest.yml → typed Entry objects
         │   Each entry: label, file, sha256, license, covers,
         │   restrict_to_covers, remap
         │
[2]  ▼  DonorLoader.load_all  (per donor:)
         │   ├─ resolve path + verify sha256 + verify magic bytes
         │   ├─ Fontisan::FontLoader.load(path)
         │   ├─ OutlinePolicy.cbdt_only?(font)?
         │   │    YES → return {font:, coverage:} (CBDT path)
         │   │    NO  → continue to UFO conversion ↓
         │   ├─ Fontisan::Ufo::Convert::FromBinData.convert(font)
         │   ├─ Ufo::Normalization.apply!(ufo, target_upm: 1000)
         │   └─ scan_ufo_coverage(ufo, entry) → filtered {cp => gid}
         │
[3]  ▼  CpMap.from_donors  (reads donor[:coverage], first-wins)
         │   ├─ filter_reserved (drop PUA/surrogate/specials)
         │   └─ backfill_cc_cf (C0/C1/Cf → .notdef)
         │
[4]  ▼  Fontisan::Stitcher::PartitionStrategy::ByPlane
         │   Groups codepoints by Unicode plane
         │   Each partition ≤ 65,535 glyphs (OpenType glyph ID cap)
         │
[5]  ▼  Otc::Build.call
         │   ├─ Stitcher.new
         │   ├─ add_source(label, ufo_or_font, remap:) per donor
         │   ├─ set_info(family, style, version, copyright)
         │   ├─ blueprint.apply_to(stitcher)
         │   └─ stitcher.write_collection(path, format: :ttc)
         │
[6]  ▼  MetricsPass.recompute!(path)
         │   Per face: walk glyf/loca → bbox union
         │   Patch head.bbox, hhea.ascent/descent, OS/2 metrics
         │   from actual glyph extents (not frozen Latin profile)
         │
[7]  ▼  verify.rb  (assertions:)
         upm == 1000 per face
         glyph count ≤ 65,535 per face
         cmap union ≥ 99% of assigned Unicode 17
         no face has head.yMax > 1200
```

## Module guide

### Essenfont::Manifest
- `Collection` — enumerable of entries, loaded from YAML
- `Entry` — one donor declaration (label, file, sha256, license, covers, etc.)

### Essenfont::Donor
- `Info` — typed value object (Struct) for a loaded donor. Replaces the
  shapeless hash DonorLoader previously returned. Carries `label`, `font`,
  `ufo`, `coverage`, `remap`, `entry`, `native_upm`, `scale_factor`.
- `Info#outline_source` — returns `ufo || font`. The single place the
  UFO-or-font fallback lives; callers no longer repeat `d[:ufo] || d[:font]`.
- `Info#cbdt?` — true when the donor was loaded via the CBDT bitmap path.

### Essenfont::DonorLoader
- `load_all` → `{label => Donor::Info}`
- `load_one(entry)` → `Donor::Info` (or nil on skip)
- CBDT donors: `font` set, `ufo` nil (bitmap path bypasses UFO)
- Outline donors: `ufo` set (normalized to target UPM), `font` also retained

### Essenfont::Ufo::Normalization
- `apply!(ufo, target_upm: 1000)` — per-donor uniform UPM scaling
- Scales: glyph contours, advance widths, font-info metric fields
- Defers: kerning, anchors (future release)
- `identity?` — true when source UPM == target (no-op optimization)

### Essenfont::CpMap
- `build_from(donors)` → CpMap (primary interface: scan → filter → backfill in one call)
- `from_donors(donors)` → CpMap (scan only; reads `donor.coverage` Hash directly)
- `filter_reserved` → drops PUA/surrogate/specials
- `backfill_cc_cf` → C0/C1/Cf codepoints → .notdef
- `donor_labels` → `{cp => label}` view (for Stitcher PartitionStrategy)

### Essenfont::OutlinePolicy
- `cbdt_only?(font)` — true if font has CBDT/CBLC but no glyf/CFF/CFF2
- `outline_eligible(donors)` — filters out CBDT donors for CpMap

### Essenfont::Otc::Build
- Orchestrates: partition → add sources → stitch → write → MetricsPass
- `call(output_path:)` → Result with output_path, bytes, subfonts (collection path)
- `write_per_plane_ttfs(out_dir:)` → Array of {name:, path:, bytes:} (per-plane TTFs)
- `call_single_face(output_path:, format:)` → path (legacy BMP-only TTF/OTF)
- All three use `donor.outline_source` (ufo || font) — no caller can mistype the fallback

### Essenfont::Otc::MetricsPass
- `recompute!(ttc_path)` — patches head/hhea/OS-2 per face from glyph extents
- Binary-level surgery (fontisan tables are read-only in 0.4.23)
- Per-face: Latin floor (asc=800, desc=-200), grows for tall scripts
- Internal classes: `SfntTableDirectory` (shared table-directory parser),
  `FaceTableLocator`, `GlyphExtentsScanner`, `FaceMetricsPatcher`, `Extents`

### Essenfont::Otc::Naming
- `FAMILY`, `SUBFAMILY`, `COPYRIGHT` constants
- `version_string`, `version_major`, `version_minor`

## Design decisions

### Why UFO-driven build (v0.2.9+)

Previously, donor TTFs were passed directly to the Stitcher, which
copied raw glyph coordinates. When donor UPM ≠ target UPM, glyphs
landed at wrong scales (e.g., 2048-upm donor in 1000-upm face =
2× overflow).

The UFO-driven approach:
1. Converts each donor TTF → UFO (Fontisan::Ufo::Convert::FromBinData)
2. Normalizes each UFO to target UPM (Essenfont::Ufo::Normalization)
3. Passes normalized UFOs to Stitcher

Per-donor uniform scaling preserves each donor's internal design
proportions. This is the Noto Sans workflow adapted for compiled
donor fonts.

### Why target UPM = 1000

134 of 148 donors ship at native `unitsPer_em = 1000` (PostScript
convention). Choosing 1000 as target means 90% of donors need zero
scaling. The remaining 14 donors (FSung at 1024, egyptiantext at
2048, Lentariso at 2400, etc.) scale per-donor with one uniform
factor each.

### Why per-face metrics from actual glyphs

fontisan's Stitcher inherits each face's head/hhea/OS-2 from one
of its donors. The inherited metrics are frozen at that donor's
profile — typically Latin (ascent=800, descent=-200). Faces with
taller glyphs (Tangut, Egyptian Hieroglyphs, Cuneiform) overflow.

MetricsPass walks each face's glyf table after the Stitcher writes
the file, computes the actual bbox union, and patches head.bbox +
hhea + OS/2 to accommodate the tallest glyphs. This is what Noto
Sans does — each face's metrics match its script's extents.

### Why restrict_to_covers enforced at CpMap

The `restrict_to_covers: true` flag in manifest.yml tells the build
that a donor should ONLY contribute codepoints within its `covers:`
blocks. Without enforcement, donors with rich cmaps (like FSung,
which includes Basic Latin) leak into CpMap and claim codepoints
outside their intended scope.

CpMap reads `donor[:coverage]` (pre-filtered by DonorLoader) instead
of rescanning the raw font's cmap. This makes CpMap the single
enforcement point.

### Why FSung for CJK

FSung (Full-Sung 全宋體) by F.G. Wang / Taiwan MOE is the
authoritative Traditional-first CJK font covering every Unicode 17
CJK extension through Ext J. It ships as 4 separate TTFs (m/2/3/X)
because each TTF can hold at most 65,535 glyphs.

License: FSung-NC (non-commercial). The build propagates this
restriction to the output font's name table (nameID 0 + 13).

### Why uni-hieroglyphica for Egyptian Hieroglyphs

Michel Suignard (suignard.com) co-edited the Unicode Egyptian
Hieroglyphs block. His UniHieroglyphica font is the canonical
academic reference, at upm=1000 (no scaling needed). Previous
primary (egyptian-text/eot.ttf at upm=2048) is now defense-in-depth.

## Autoload convention

All library modules resolve via Ruby `autoload`, not `require_relative`.

- Root: `lib/essenfont.rb` registers top-level autoloads
- Sub-namespaces: `lib/essenfont/otc.rb`, `lib/essenfont/ufo.rb`,
  `lib/essenfont/manifest.rb` register their children
- External gems: `require "fontisan"`, `require "ucode"`, `require "digest"`,
  `require "yaml"` — these are external dependencies, not library code

Never use `require_relative` for library code. It pollutes the load
path and defeats lazy loading.

## Adding a donor

See [adding-a-donor.md](adding-a-donor.md).

## Debugging a glyph

See [debugging.md](debugging.md).
