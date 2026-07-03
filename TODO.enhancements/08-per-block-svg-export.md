# 08 — Per-Block SVG Export

## Goal

Every codepoint's SVG outline available at
`https://essenfont.github.io/svg/U+XXXX.svg`. Type designers,
researchers, OCR model trainers, and educators want individual SVGs.

Trivial to generate during the build — we already have the outlines.

## Format

Per-codepoint SVG, 1000×1000 viewBox, nofill, single path:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
  <metadata>
    <codepoint>U+1F600</codepoint>
    <name>GRINNING FACE</name>
    <donor>noto-color-emoji</donor>
    <license>OFL-1.1</license>
    <essenfont-version>0.2.0</essenfont-version>
  </metadata>
  <path d="M ... Z"/>
</svg>
```

## Generation pipeline

New script: `scripts/emit_svg_exports.rb`

Inputs:
- `Essenfont-Regular.otc` (or per-plane TTFs)
- `provenance.json` (from TODO 03) for donor attribution

Output: `svg-exports/` directory with one SVG per codepoint, plus
`svg-exports/index.json` manifest:

```json
{
  "essenfont_version": "0.2.0",
  "generated_at": "2026-07-15T10:00:00Z",
  "total_svgs": 131193,
  "files": {
    "1F600.svg": { "cp": "0x1F600", "name": "GRINNING FACE", "donor": "noto-color-emoji" },
    ...
  }
}
```

Implementation using fontisan:

```ruby
require "fontisan"

reader = Fontisan::Collection::Reader.open("Essenfont-Regular.otc")
reader.each_face do |face|
  face.table("cmap").unicode_mappings.each do |cp, gid|
    glyph = face.glyph_for_gid(gid)  # or similar API
    svg_path = glyph.to_svg_path  # converts TrueType contours to SVG path
    metadata = { codepoint: "U+#{cp.to_s(16)}", donor: donor_for_cp(cp) }
    File.write("svg-exports/U+#{cp.to_s(16).upcase}.svg", render_svg(svg_path, metadata))
  end
end
```

## Release artifacts

- `svg-exports.zip` — single ZIP with all ~131k SVGs (~50 MB
  compressed, ~200 MB uncompressed)
- `svg-exports-index.json` — the manifest, downloadable separately
  (~5 MB)
- Per-plane ZIPs: `svg-exports-bmp.zip`, `svg-exports-smp.zip`,
  etc., for users who only want one plane

Release workflow uploads all of these.

## Website serving

The site doesn't host all 131k SVGs directly (too much disk). Instead:

1. Per-codepoint SVGs live in the GitHub Release ZIP
2. Website lazy-fetches on demand via a Cloudflare Worker (or
   similar) that:
   - Caches `https://essenfont.github.io/svg/U+XXXX.svg` requests
   - On cache miss, fetches from the GH release ZIP, extracts the
     single SVG, returns it
   - Caches for 1 year (immutable assets)

Simpler alternative: don't serve per-cp SVGs from the site at all.
UnicodeCharPage's "Download .svg" link goes directly to a
GitHub-release-zip-extractor URL like:

```
https://github.com/essenfont/essenfont/releases/download/v0.2/svg-exports/U+1F600.svg
```

(Requires uploading the unzipped svg-exports/ directory to the
release, not a single ZIP.)

## UnicodeCharPage wiring

Update the existing "Download .svg" link (currently a placeholder
URL pattern) to point at the real asset:

```vue
<a
  :href="`https://github.com/essenfont/essenfont/releases/latest/download/svg/U+${hex.toUpperCase()}.svg`"
>Download .svg</a>
```

Show file size estimate ("~2 KB") next to the link.

## Acceptance

- `scripts/emit_svg_exports.rb` produces svg-exports/ + index
- Release workflow uploads svg-exports.zip + per-plane ZIPs +
  per-codepoint files
- UnicodeCharPage "Download .svg" link resolves
- SVG metadata includes codepoint, name, donor, license, version
- 100% of codepoints in the build get an SVG (no missing files)
