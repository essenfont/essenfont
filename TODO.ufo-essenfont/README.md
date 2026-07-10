# TODO.ufo-essenfont — UFO-driven build, glyph-bounds fix, v0.2.9 release

## Problem

Two bugs in the current build (v0.2.8):

1. **Glyph bounds overflow**: Glyphs from non-1000-upm donors (e.g.
   `egyptiantext-COLR` at 2048-upm → `Essenfont` SMP face at 1000-upm)
   are copied with raw coordinates, making them 2× too large. 𓂀
   (U+13080) overflows its em-box.

2. **FSung scope leak**: `CpMap.new_from_scan` reads the donor font's
   raw cmap instead of the filtered coverage, so `restrict_to_covers:
   true` is never enforced. FSung-m claims Basic Latin (U+0041 →
   `fsung-m`) despite `covers:` listing only CJK blocks.

## Solution architecture

**UFO-driven build**: every donor is converted to UFO, normalized to
`unitsPerEm=1000` (per-donor uniform scale), then stitched. Per-face
vertical metrics are recomputed from actual glyph extents after
stitch. This is the Noto Sans workflow — UFOs are the intermediate
format, normalization happens at the UFO layer, and the Stitcher
copies raw coordinates from already-normalized UFOs.

## Execution order

| # | File | What | Repo |
|---|------|------|------|
| 01 | `01-cpmap-coverage-filter.md` | One-line fix: CpMap reads `d[:coverage]` not `scan_cmap(d[:font])` | build |
| 02 | `02-ufo-normalization.md` | New: `Essenfont::Ufo::Normalization` — per-donor UPM scaling | build |
| 03 | `03-metrics-pass.md` | New: `Essenfont::Otc::MetricsPass` — per-face metric recompute via binary patch | build |
| 04 | `04-donor-loader-ufo-path.md` | Rewire `DonorLoader` to convert + normalize each donor UFO | build |
| 05 | `05-autoload-registration.md` | Register new modules in root + `otc.rb` + new `ufo.rb` namespace files | build |
| 06 | `06-manifest-unihieroglyphica.md` | `uni-hieroglyphica` becomes primary for all Egyptian blocks | build |
| 07 | `07-specs.md` | RSpec coverage for all new modules | build |
| 08 | `08-architecture-docs.md` | `docs/architecture.md` + `docs/adding-a-donor.md` + `docs/debugging.md` | build |
| 09 | `09-build-and-verify.md` | Build TTC, run `verify.rb`, visual check 𓂀 + Latin + CJK | build |
| 10 | `10-release-v0.2.9.md` | VERSION bump → tag v0.2.9 → release.yml fires | build |
| 11 | `11-website-data-scripts.md` | `gen-face-table.mjs` + `gen-donor-attribution.mjs` + `gen-upm-scales.mjs` | website |
| 12 | `12-website-svg-components.md` | Data-driven SVG diagram components (TTC anatomy, donor grid, pipeline, UPM) | website |
| 13 | `13-website-specification-page.md` | `/engineering/specification` page with all diagrams | website |

## Design constraints (enforced throughout)

- **OCP**: new behaviors = new classes, not edits to existing switch statements
- **MECE**: each concern in exactly one module; no overlapping responsibilities
- **DRY**: single source of truth for target UPM, scale factors, block ranges
- **Encapsulation**: public API via `attr_reader`; no `send` to private; no `instance_variable_set/get`
- **No `respond_to?`**: use protocol contracts (documented method expectations) or `is_a?` for type checks
- **No `require_relative`**: Ruby `autoload` in parent namespace files only
- **Performance**: O(1) or O(n) per operation; no O(n²) cmap lookups
- **Specs**: every public method has at least one spec
