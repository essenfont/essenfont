# 09 — License Attribution Pack

## Goal

Per-release ZIP with machine-readable license attribution. Critical
for commercial users — the FSung-NC restriction is currently a soft
warning; this makes it actionable (programmatically strippable).

## Why

essenfont ships under a dual license:
- **OFL-1.1** for most glyphs (Noto, Lentariso, Kedebideri, etc.)
- **OFL-1.1 + FSung-NC** for CJK glyphs derived from Full-Sung
  (non-commercial restriction from F.G. Wang)

Commercial users need to either:
1. Get permission from F.G. Wang for FSung-derived glyphs, OR
2. Strip FSung-derived glyphs and lose CJK coverage

Both require knowing exactly which codepoints are FSung-derived.
Currently that data lives in `sources/manifest.yml` but isn't
surfaced per-codepoint.

## Pack contents

### LICENSE-SOURCES.md

Human-readable per-donor attribution with codepoint ranges:

```markdown
# Essenfont v0.2.0 — License Sources

This release is assembled from N donor fonts. Per-donor attribution:

## Noto Sans (OFL-1.1)

- Files: NotoSans-Regular.ttf, NotoSans-Bold.ttf, ...
- sha256: ...
- Covers:
  - Basic Latin (U+0020..U+007E) — 95 cps
  - Latin-1 Supplement (U+00A0..U+00FF) — 96 cps
  - ...
- Total: 12,345 cps
- Source: https://fonts.google.com/noto

## Full-Sung (FSung) (OFL-1.1 + FSung-NC)

- Files: FSung-m.ttf, FSung-2.ttf, FSung-3.ttf, FSung-X.ttf
- sha256: ...
- Covers:
  - CJK Unified Ideographs (U+4E00..U+9FFF) — 20,992 cps
  - CJK Ext B (U+20000..U+2A6DF) — 42,718 cps
  - ...
- Total: 65,432 cps
- Restriction: non-commercial use only for these glyphs.
  See https://fgwang.blogspot.com/ for permission.

## ...

## Summary

- OFL-only cps: 65,000 (49%)
- FSung-NC cps: 65,432 (49%) — non-commercial restriction applies
- Other cps: 4,000 (2%) — see per-donor entries
```

### license-overview.csv

Machine-readable, one row per donor:

```csv
donor,license,covers_count,first_cp,last_cp,source_url,sha256
noto-sans,OFL-1.1,12345,0020,007E,https://fonts.google.com/noto,abc123
fsung,OFL-1.1+FSung-NC,65432,4E00,2A6DF,https://fgwang.blogspot.com/,def456
...
```

### fsung-nc-filter.txt

The list of codepoints subject to the FSung-NC restriction. One cp
per line, hex format:

```
4E00
4E01
4E02
...
2A6DF
```

Use case: commercial user runs `comm -23 my-cps.txt fsung-nc-filter.txt`
to find which of their needed cps are NOT subject to NC, then builds
a subset OTC with only the OFL-pure cps.

### LICENSE.md

Concatenation of every donor's LICENSE file, separated by `---`.

## Build script

New: `scripts/emit_license_pack.rb`

Inputs:
- `sources/manifest.yml` — donor registry
- `references/input-fonts/ATTRIBUTIONS.md` — full attribution
- `cp_map` — per-cp donor assignment (from build.rb)
- `references/input-fonts/<donor>/LICENSE` — per-donor license files

Outputs (to `license-pack/`):
- `LICENSE-SOURCES.md`
- `license-overview.csv`
- `fsung-nc-filter.txt`
- `LICENSE.md`
- `license-pack.zip` (all of the above)

Implementation:

```ruby
module EmitLicensePack
  def self.emit(manifest_path:, cp_map:, out_dir:)
    manifest = YAML.safe_load(File.read(manifest_path))
    donors = manifest["donors"]

    # Group codepoints by donor
    cps_by_donor = cp_map.group_by { |_cp, info| info[:label] }

    # Emit LICENSE-SOURCES.md
    emit_markdown(donors, cps_by_donor, out_dir)

    # Emit CSV
    emit_csv(donors, cps_by_donor, out_dir)

    # Emit FSung-NC filter
    emit_fsung_filter(donors, cps_by_donor, out_dir)

    # Concat LICENSE files
    concat_license_files(donors, out_dir)

    # Zip
    zip_dir(out_dir)
  end
end
```

## Release workflow integration

In `.github/workflows/release.yml`:

```yaml
- name: Emit license attribution pack
  run: bundle exec ruby scripts/emit_license_pack.rb

- name: Upload license pack
  uses: softprops/action-gh-release@v2
  with:
    files:
      - license-pack.zip
      - license-pack/LICENSE-SOURCES.md
      - license-pack/license-overview.csv
      - license-pack/fsung-nc-filter.txt
```

## Website: /license page

New page summarizing the license model. Sections:

1. **Most glyphs**: OFL-1.1 — standard terms
2. **CJK glyphs from Full-Sung**: OFL-1.1 + FSung-NC — non-commercial
3. **How to comply**: link to license pack, link to FSung-NC filter
4. **How to request commercial permission**: link to F.G. Wang's blog

Acceptance:
- Page exists at `/license`
- Links to the latest license pack artifacts
- Includes a copyable command for filtering FSung-NC cps

## Acceptance

- `scripts/emit_license_pack.rb` produces all 4 files + ZIP
- Release workflow uploads them
- /license page exists with the above sections
- LICENSE-SOURCES.md is accurate (donor cps match the build)
- fsung-nc-filter.txt contains exactly the FSung-derived cps
- license-overview.csv opens cleanly in Excel/Numbers
