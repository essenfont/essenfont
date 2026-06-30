# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) for working in this repository.

## Project purpose

essenfont is **a real font**, not a library or gem. It is a single
redistributable OpenType font that covers every assigned Unicode 17
codepoint (~299,382 glyphs across ~346 blocks). The output is
`Essenfont-Regular.ttf` distributed via GitHub Releases.

essenfont is **100% donor-derived** — every glyph is vector-extracted
from canonical OFL-licensed donor fonts (Noto family, Full-Sung,
Lentariso, Kedebideri, UniHieroglyphica, etc.). There is **no UFO
source, no hand-designed glyphs**. The build is purely an assembly
pipeline: read donors → extract glyphs → assemble TTF.

## Architecture

```
ucode universal-set manifest (per-cp donor mapping)
       │
       ▼
scripts/build.rb
  │  reads sources/manifest.yml (donor registry)
  │  opens each donor via fontisan
  │  for each codepoint: extracts glyf from donor
  │  assembles all OpenType tables via Fontisan::FontBuilder
  │  writes Essenfont-Regular.ttf via Fontisan::FontWriter
  ▼
scripts/verify.rb
  round-trip validation via Fontisan::FontLoader
```

### Key files

| Path | Purpose |
|---|---|
| `sources/manifest.yml` | Donor font registry (label, file, sha256, license, covers) |
| `references/input-fonts/` | Actual donor TTF/OTF files (committed to git — ~227MB) |
| `references/input-fonts/ATTRIBUTIONS.md` | Full attribution per donor (author, URL, license) |
| `scripts/build.rb` | The build: donors → Essenfont-Regular.ttf |
| `scripts/verify.rb` | Round-trip validation |
| `TODO.essenfont/` | Build phase plans |
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
uses Noto Sans Tangut.

## Dependencies

- **fontisan** — font parsing + writing (read donors, write output TTF)
- **ucode** — universal-set manifest (per-cp donor mapping)
- Ruby 3.2+

No AFDKO, no Python fonttools, no makeotc. Pure Ruby + fontisan.

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

# Build the font
ruby scripts/build.rb

# Verify
ruby scripts/verify.rb Essenfont-Regular.ttf
```

## Release

Binary output (`Essenfont-Regular.ttf`) is distributed via GitHub
Releases only — NEVER committed to the repo. Tag a release:

```bash
git tag v0.1.0
git push origin v0.1.0
# CI builds the TTF and attaches it to the GitHub Release
```
