# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) for working in this repository.

## Project purpose

essenfont is **a real font**, not a library or gem. It is a single
redistributable OpenType Collection (OTC) that covers every assigned
Unicode 17 codepoint (~131,000 unique glyphs partitioned across 5
plane subfonts). The output is `Essenfont-Regular.otc` (CFF2 outlines,
canonical) or `Essenfont-Regular.ttc` (glyf outlines, fallback),
distributed via GitHub Releases.

essenfont is **100% donor-derived** — every glyph is vector-extracted
from canonical OFL-licensed donor fonts (Noto family, Full-Sung,
Lentariso, Kedebideri, UniHieroglyphica, etc.). There is **no UFO
source, no hand-designed glyphs**. The build is purely an assembly
pipeline: read donors → partition by plane → stitch into 5 subfonts →
pack into a collection.

## Architecture

```
ucode universal-set manifest (per-cp donor mapping)
       │
       ▼
scripts/build.rb
  │  reads sources/manifest.yml (donor registry)
  │  opens each donor via fontisan
  │  for each codepoint: extracts glyf from donor
  │  partitions codepoints by Unicode plane (BMP/SMP/SIP/TIP/SSP)
  │  Essenfont::Otc::Build orchestrates:
  │    PlanePartitioner → Blueprint → StitcherSession
  │    → Stitcher#include_codepoints(into: :plane_N) for each plane
  │    → Stitcher#write_collection → Essenfont-Regular.{otc,ttc}
  ▼
scripts/verify.rb
  round-trip validation via Fontisan::FontLoader
```

### The OTC subsystem — `lib/essenfont/otc/`

A small Ruby subsystem under `lib/essenfont/` that delegates almost
everything to fontisan and ucode. Top-level autoload root:
`lib/essenfont.rb`.

| Class / module              | Responsibility                                             |
|-----------------------------|------------------------------------------------------------|
| `Essenfont::Otc::Build`     | Top-level orchestrator; thin glue over `Fontisan::Stitcher` + `PartitionStrategy::ByPlane` + `Ucode::Unicode` |
| `Essenfont::Otc::Naming`    | Essenfont-specific constants (FAMILY, VERSION, SUBFAMILY, COPYRIGHT) |
| `Essenfont::Otc::Errors`    | Essenfont error namespace                                  |
| `Essenfont::Otc::Version`   | `STRING = "0.1.0"`                                         |

What used to live here but is now upstream:

| Concept | Where it lives now |
|---------|-------------------|
| Unicode plane value object + catalog | `Ucode::Unicode.for_version` (ucode gem) |
| Block value object + catalog | `Ucode::Unicode.for_version` (ucode gem) |
| Partition + Blueprint + Partitioner | `Fontisan::Stitcher::PartitionStrategy::*` (fontisan 0.4.7+) |
| Plane partitioner | `Fontisan::Stitcher::PartitionStrategy::ByPlane` (fontisan 0.4.7+) |
| Per-cp donor assignment batch | `Fontisan::Stitcher#include_codepoints_map` (fontisan 0.4.7+) |
| Collection stats reader | `Fontisan::Collection::Reader` (fontisan 0.4.7+) |
| Per-subfont name helper | `Fontisan::Ufo::Info.for_subfont` (fontisan 0.4.7+) |
| Multi-format WOFF encoding | `fontisan convert INPUT.ttf --to woff,woff2` CLI (fontisan 0.4.7+) |
| Collection validation CLI | `fontisan validate collection PATH` (fontisan 0.4.7+) |
| Assigned Unicode codepoint count | `Ucode::Unicode.assigned_count` (ucode 0.3.0+) |

The subsystem uses **autoload only** — no `require_relative`, no
`send`, no `instance_variable_set/get`, no `respond_to?`. Specs use
real `Fontisan::Stitcher` instances and real donor TTFs (no doubles).

### Key files

| Path | Purpose |
|---|---|
| `sources/manifest.yml` | Donor font registry (label, file, sha256, license, covers) |
| `references/input-fonts/` | Actual donor TTF/OTF files (committed to git — ~227MB) |
| `references/input-fonts/ATTRIBUTIONS.md` | Full attribution per donor (author, URL, license) |
| `lib/essenfont.rb` | Autoload root for the OTC subsystem |
| `lib/essenfont/otc.rb` | `module Otc` — autoloads Build, Naming, Errors, Version |
| `lib/essenfont/otc/build.rb` | Top-level orchestrator (~70 lines) |
| `scripts/build.rb` | Main build: donors → Essenfont-Regular.{otc,ttc} |
| `scripts/emit_coverage_manifest.rb` | Build output → `coverage.json` for the website (uses `Ucode::Unicode` + `Collection::Reader`) |
| `scripts/verify.rb` | Round-trip validation |
| `spec/` | RSpec suite (~74 examples, real fontisan integration) |
| `TODO.otc-essenfont/` | 10 spec docs covering the OTC pipeline + website + GHA |
| `TODO.full/` | Earlier work phases |
| `.github/workflows/ci.yml` | Specs + smoke-build on push/PR |
| `.github/workflows/release.yml` | Tag `v*` → build → GitHub Release |
| `README.adoc` | Public README |
| `LICENSE` | SIL OFL 1.1 (the assembled font) |

### No UFO source

essenfont does NOT have `font.ufo/`. Every glyph comes from a donor
font. If a glyph needs correction, fix the upstream donor — essenfont
picks it up on the next donor-version bump.

### CJK donor: Full-Sung (not Noto)

For CJK Unified Ideographs (all extensions), essenfont uses the
Taiwan MOE 全宋體 (Full-Sung) family by lxs602:
- Repo: https://github.com/lxs602/FSung-font
- Web: https://fgwang.blogspot.com/2025/09/unicode-17.html
- Covers Ext A–J including Unicode 17 Ext J (U+31350..U+323AF)
- Multi-file: FSung-m (BMP), FSung-2 (SIP), FSung-3 (TIP+Ext J), FSung-X (Plane 3)

Noto Sans CJK is NOT used for CJK ideographs. Tangut (separate script)
uses Noto Serif Tangut.

## Dependencies

- **fontisan** (≥ 0.4.7) — Stitcher (with `include_codepoints_map`),
  `PartitionStrategy::ByPlane`, `Collection::Reader`, `Collection::Builder`,
  `Ufo::Info.for_subfont`, `Converters::Woff*Encoder`, `Ufo::Compile::Otf2Compiler`,
  and the `fontisan convert --to woff,woff2` / `fontisan validate collection` CLIs
- **ucode** (≥ 0.3.0) — `Ucode::Unicode` Ruby API (Plane, Block,
  Catalog, assigned_count) + `ucode fetch fonts` CLI for donor acquisition
- Ruby 3.2+

No AFDKO, no Python fonttools, no makeotc. Pure Ruby + fontisan + ucode.

## Global rules (from ~/.claude/CLAUDE.md)

The global CLAUDE.md rules apply in full:
- NEVER delete source files
- NEVER push tags, commit to main, or merge to main without explicit authorization
- NEVER add AI attribution
- NEVER use `double()` in specs
- NEVER hand-roll serialization — use lutaml-model mappings
- NEVER use `require_relative` — use Ruby autoload
- NEVER use `send` / `instance_variable_set` / `respond_to?`
- Always ASK before destructive actions

## Build / test

```bash
# Acquire donor fonts (FSung must be local; Noto fetched via ucode)
cp ~/Downloads/全宋體/FSung-*.ttf references/input-fonts/
cd ../ucode && bundle exec ucode fetch fonts && cp data/fonts/* ../essenfont/references/input-fonts/

# Build (default: OTC with glyf outlines — TTC container)
ruby scripts/build.rb

# Alternative formats
ruby scripts/build.rb --format=otc-cff2    # CFF2 outlines — OTC container, ~35% smaller
ruby scripts/build.rb --format=ttf-per-plane  # per-plane TTFs for legacy clients
ruby scripts/build.rb --format=ttf         # legacy single BMP-only TTF

# Encode per-plane WOFF/WOFF2 for web embedding (fontisan convert --to woff,woff2)
for plane in BMP SMP SIP TIP SSP; do
  fontisan convert Essenfont-${plane}.ttf --to woff,woff2 --output Essenfont-${plane}
done

# Emit coverage manifest for the website (uses Ucode::Unicode)
ruby scripts/emit_coverage_manifest.rb > coverage.json

# Run specs
bundle exec rspec

# Verify the output
ruby scripts/verify.rb Essenfont-Regular.otc
```

## Release

Binary outputs (`Essenfont-Regular.{otc,ttc}`, per-plane TTFs, per-plane
WOFF/WOFF2, `coverage.json`) are distributed via GitHub Releases only —
NEVER committed to the repo. Tag a release:

```bash
echo "0.2.0" > VERSION
git commit -am "chore: bump version to 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
# CI (.github/workflows/release.yml) builds all formats and uploads
# the GitHub Release. The website (essenfont/essenfont.github.io)
# polls every 6h for new releases and redeploys automatically.
```

See `TODO.otc-essenfont/09-release-pipeline.md` for the full release
architecture.
