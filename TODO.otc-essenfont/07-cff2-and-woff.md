# 07 — CFF2 Outlines + WOFF/WOFF2 Emission

## Context

`fontisan` (post-0.4.6) ships two independent capabilities essenfont now consumes:

1. **CFF2 subfont outlines** — `Fontisan::Ufo::Compile::Otf2Compiler` builds
   CFF2 charstrings from TTF outlines. CFF2 is smaller than glyf and supports
   variable-font extensions for free.
2. **WOFF/WOFF2 packaging** — `Fontisan::Pipeline::OutputWriter` encodes
   per-table brotli (WOFF2) or zlib (WOFF) compression of an SFNT font.
   `WoffFont#to_ttf` and `Woff2Font#to_ttf` decode back to SFNT.

WOFF2 is the only sensible web-embed format for a font this large. OTC is
not browser-embeddable (`@font-face` rejects collection containers).

## What we ship

For each release tag `vX.Y.Z`, the build emits:

| Path                               | Format     | Audience                         |
|------------------------------------|------------|----------------------------------|
| `Essenfont-Regular.otc`            | OTC, glyf | Desktop install (canonical)      |
| `Essenfont-CFF2-Regular.otc`       | OTC, CFF2 | Desktop install (compact modern) |
| `Essenfont-BMP.ttf`                | TTF, glyf | Legacy BMP-only fallback         |
| `Essenfont-SMP.ttf`                | TTF, glyf | Per-plane fallback               |
| `Essenfont-SIP.ttf`                | TTF, glyf | Per-plane fallback (CJK)         |
| `Essenfont-TIP.ttf`                | TTF, glyf | Per-plane fallback (Tangut etc.) |
| `Essenfont-SSP.ttf`                | TTF, glyf | Per-plane fallback (tags)        |
| `Essenfont-BMP.woff2`              | WOFF2     | `@font-face` web embed           |
| `Essenfont-SMP.woff2`              | WOFF2     | `@font-face` web embed           |
| `Essenfont-SIP.woff2`              | WOFF2     | `@font-face` web embed           |
| `Essenfont-TIP.woff2`              | WOFF2     | `@font-face` web embed           |
| `Essenfont-SSP.woff2`              | WOFF2     | `@font-face` web embed           |
| `Essenfont-BMP.woff`               | WOFF      | Legacy web (IE11)                |
| `...`                              | WOFF      | (per-plane, as above)            |
| `coverage.json`                    | JSON      | Manifest for the website         |

The website serves the OTC as the canonical download and the per-plane
WOFF2s as `@font-face` sources with `unicode-range` declarations.

## CFF2 outline option

`Essenfont::Otc::Build` already accepts `subfont_format: :otf2` (the
`SUBFONT_FORMATS = %i[ttf otf otf2]` constant in
`Essenfont::Otc::Writer`). The build pipeline exposes a CLI flag:

```
ruby scripts/build.rb --format=otc           # default: glyf subfonts in OTC
ruby scripts/build.rb --format=otc-cff2      # alternative: CFF2 subfonts in OTC
```

CFF2 subfonts are ~30–40% smaller than glyf subfonts but require
CFF-aware consumers (any modern OS / browser). The website default is
the glyf OTC; CFF2 is offered as a "modern, compact" alternative.

## Why CFF2 vs CFF1?

CFF2 (OpenType 1.8+) supports:
- **Variation stores** — HVAR/VORG/MVAR optimizations
- **Smaller file size** via improved subroutinization
- **Mixed-mode** — variable and static in the same table

CFF1 (the original `CFF ` table) is the older format. fontisan's
`Otf2Compiler` produces CFF2; `OtfCompiler` produces CFF1. essenfont
uses CFF2 for the modern path; CFF1 is not shipped (no upside vs CFF2).

## WOFF2 emission

`scripts/encode-woff.rb` is a thin wrapper around
`Fontisan::Pipeline::OutputWriter`:

```ruby
# Reads an SFNT (TTF or OTF) and writes WOFF + WOFF2 alongside.
require "fontisan"

input = ARGV.fetch(0)
basename = input.sub(/\.ttf$|\.otf$/, "")

tables = Fontisan::FontLoader.load(input).tap do |font|
  # Collect raw table bytes
end.each_with_object({}) do |font, h|
  font.table_names.each { |tag| h[tag] = font.table(tag).raw_data }
end

Fontisan::Pipeline::OutputWriter.new("#{basename}.woff", :woff).write(tables)
Fontisan::Pipeline::OutputWriter.new("#{basename}.woff2", :woff2).write(tables)
```

This is called from the build pipeline after `build_per_plane_ttfs`.

## Why per-plane WOFF2 instead of per-block?

The current site already ships ~214 per-block WOFF2 files (~80 KB each,
total ~17 MB). They're served via `@font-face unicode-range` so a visitor
viewing one page fetches only the blocks they need.

Per-plane WOFF2s are the **whole-font web embed** for users who want a
single CSS rule covering an entire plane. They're larger (BMP is ~12 MB
WOFF2 vs 80 KB for a single block) but simpler to deploy.

Both sets are shipped:
- **Per-block WOFF2** — drives the interactive site (`/unicode`, `/donors`)
- **Per-plane WOFF2** — for external sites that want a one-line embed

## Build-time cost

| Step                         | Time (CI) | Notes                                    |
|------------------------------|-----------|------------------------------------------|
| Donor acquisition            | ~3 min    | fontist fetch + ucode fetch              |
| TTF stitch (glyf, 5 subfonts)| ~6 min    | Donor → 5 subfonts                       |
| CFF2 stitch (5 subfonts)     | ~10 min   | CFF2 charstring compilation is slower    |
| Per-plane WOFF2 encode       | ~30 s     | Brotli on each plane                     |
| Per-block WOFF2 subset       | ~3 min    | Existing site build step                 |
| **Total**                    | **~22 min** | Acceptable for release-tag builds       |

The CFF2 path is opt-in via `--format=otc-cff2`. Default release builds
emit glyf OTC + per-plane TTFs + per-plane WOFF2 (~12 min total).

## Quality gates

Before tagging a release, the build verifies:

1. **OTC has N faces** — `ttc-header.numFonts == blueprint.subfont_count`
2. **Each face under cap** — `maxp.num_glyphs ≤ 65,535` for every face
3. **Union of cmaps ≥ input cp_map × 0.99** — no silent drops
4. **CFF2 charstring round-trip** — load each CFF2 face, decode all charstrings, no errors
5. **WOFF2 round-trip** — load each WOFF2 via `Fontisan::Woff2Font.from_file`,
   decode to SFNT, load via `FontLoader`, cmap matches source

Any failure aborts the release. No partial artifacts published.
