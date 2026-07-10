# Adding a donor

## Prerequisites

- The font must be OFL-compatible (OFL, Apache, MIT, BSD, CC0, UFL,
  Bitstream, GUST, CC-BY) or accepted-with-conditions (FSung-NC).
- If non-commercial, the restriction must be declared in
  `sources/manifest.yml` under `accepted_with_conditions:`.
- The font binary goes in `references/input-fonts/` (gitignored).
- Its sha256 must be recorded in the manifest.

## Steps

### 1. Obtain the font

Download from the upstream source. Record the URL in the manifest
entry's `url:` field. If the font is inside a zip/tarball, also
record `url_extract:` and `url_extract_member:`.

### 2. Compute sha256

```bash
sha256sum references/input-fonts/YourFont-Regular.ttf
```

### 3. Add entry to `sources/manifest.yml`

```yaml
  - label: your-font
    file: references/input-fonts/YourFont-Regular.ttf
    family: Your Font
    style: Regular
    license: OFL
    sha256: "abc123..."  # from step 2
    url: https://example.com/YourFont-Regular.ttf
    author: "Author Name"
    covers:
      - Block_Name_1
      - Block_Name_2
    restrict_to_covers: true   # recommended: limits to covers only
    notes: "What this donor provides and why."
```

**Block names** must match the underscored Unicode block identifiers
used by ucode's manifest (e.g., `CJK_Unified_Ideographs`,
`Egyptian_Hieroglyphs`, `Basic_Latin`).

**restrict_to_covers**: Set to `true` if the donor's cmap contains
codepoints outside its intended scope (e.g., a CJK font that also
ships Latin glyphs). The build will filter to only the `covers:`
blocks. Default: false (all cmap entries accepted).

### 4. Place the font binary

```bash
cp YourFont-Regular.ttf references/input-fonts/
```

### 5. Build

```bash
bundle exec ruby scripts/build.rb --format=ttc
```

Watch the output for:
```
  loaded your-font (ufo): 1234 cps [upm 1024→1000 ×0.9766]
```

If you see `skip: donor your-font — sha256 mismatch`, the file has
changed since the manifest entry was written. Update the sha256 or
re-download.

### 6. Verify

```bash
bundle exec ruby scripts/verify.rb Essenfont-Regular.ttc
```

All assertions must pass:
- head.unitsPerEm == 1000 per face
- glyph count ≤ 65,535 per face
- cmap union ≥ 99% of assigned Unicode 17
- no face has head.yMax > 1200

### 7. Check coverage

```bash
bundle exec ruby -e '
  require "essenfont"
  manifest = Essenfont::Manifest.load
  donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
  cp_map = Essenfont::CpMap.from_donors(donors)
  puts "your-font covers: #{cp_map.by_donor["your-font"]&.size || 0} codepoints"
'
```

## UPM considerations

If the donor's native `unitsPerEm` ≠ 1000, the UFO normalization
module scales all glyph coordinates uniformly. The scale factor is
`1000 / native_upm`. Check the build log for the `[upm N→1000 ×F]`
annotation.

Common UPMs:
- 1000: PostScript convention (Adobe, Noto Sans) — no scaling
- 1024: TrueType binary convention (FSung, some CJK) — ×0.9766
- 2048: TrueType v2 / emoji convention — ×0.4883
- 2400+: custom — per-donor factor

## CBDT donors

If the font is color-bitmap only (CBDT + CBLC tables, no glyf/CFF),
the build skips UFO conversion and passes the raw font to the
Stitcher's CBDT propagation path. Set `covers:` normally; the
OutlinePolicy module detects CBDT automatically.
