# sources/

Third-party fonts used as glyph donors when building essenfont.

## What lives here

```
sources/
├── manifest.yml              # donor font registry (label, file, license, sha256, covers)
├── README.md                 # this file
├── fonts/                    # actual .ttf/.otf/.ttc files (gitignored — see below)
│   ├── NotoSans-Regular.ttf
│   ├── NotoSansCJK-Regular.ttc
│   ├── FSung-1.ttf           # local-only (Taiwan 全宋體 by F.G. Wang, non-commercial)
│   ├── Lentariso-Regular.otf
│   ├── Kedebideri-Regular.ttf
│   ├── NotoSerifTaiYo.ttf    # local-only (translationcommons.org pre-release)
│   ├── UniHieroglyphica.ttf
│   ├── EgyptianText-Regular.ttf
│   ├── BabelStonePseudographica.ttf
│   ├── Symbola.ttf
│   ├── NotoEmoji-Regular.ttf
│   ├── NotoSansMath-Regular.ttf
│   ├── NotoMusic-Regular.ttf
│   ├── NotoSansTangut-Regular.ttf
│   ├── NotoSansSharada-Regular.ttf
│   ├── NotoSansTolongSiki-Regular.ttf
│   └── LastResortHE-Regular.ttf
└── licenses/                 # each donor's OFL/license file (gitignored)
    ├── NotoSans-OFL.txt
    ├── FSung-NC.txt
    └── ...
```

## `fonts/` is gitignored

Font files are NOT committed to the essenfont repo:

- They can be large (NotoSansCJK is 18MB; NotoSans full is 8MB)
- They are redistributed under OFL which requires attribution but
  allows free redistribution — keeping them out of git keeps the
  repo lean and makes license auditing easier
- The build script verifies each donor's sha256 against `manifest.yml`

## Acquiring donors

### Auto-downloadable (via ucode fetch fonts)

```bash
# In the ucode repo:
cd /path/to/ucode
bundle exec ucode fetch fonts

# Then copy to essenfont:
cp /path/to/ucode/data/fonts/*.ttf /path/to/essenfont/sources/fonts/
cp /path/to/ucode/data/fonts/*.otf /path/to/essenfont/sources/fonts/
cp /path/to/ucode/data/fonts/*.ttc /path/to/essenfont/sources/fonts/
```

ucode's `config/specialist_fonts.yml` declares each specialist's
download URL + sha256. ucode downloads + verifies automatically.

### Manual (path_local_only entries)

These donors are not available via URL (proprietary distribution
channels, pre-release, or academic sources):

| Donor | Acquisition |
|---|---|
| `fsung-*` (FSung — Taiwan 全宋體 by F.G. Wang) | Download from F.G. Wang's Google Drive: https://drive.google.com/file/d/1m0-WYAXbEz3lxJrti25ZvWv6LkHjMp2X/view?usp=sharing . Place at `sources/fonts/FSung-*.ttf`. **License is custom non-commercial share + use (NOT OFL).** |
| `noto-serif-tai-yo` | Pre-release Noto variant; contact translationcommons.org maintainers; place at `sources/fonts/NotoSerifTaiYo.ttf` |

The build script verifies sha256 against `manifest.yml` to ensure
the user supplied the expected version.

## The manifest file

See `manifest.yml` (TODO.essenfont/08 for the spec). Each entry
declares:

- `label` — stable identifier used in ucode's universal-set manifest
- `file` — relative path under `sources/fonts/`
- `family` + `style` + `version` — human-readable metadata
- `license` — see `ofl_compatible_licenses` in `manifest.yml` for
  accepted values. Custom non-OFL licenses (e.g. FSung's
  non-commercial grant) require an explicit entry in the allowed list
  — the build will refuse them otherwise.
- `sha256` — content hash for verification
- `url` + `url_extract_member` (optional) — download URL + which
  file to extract from the downloaded archive
- `path_local_only` (optional) — true if the donor must be supplied
  manually
- `font_index` (optional, TTC only) — which face to use
- `covers` — list of Unicode block IDs this donor covers (informational)
- `notes` — free-text rationale

## License enforcement

The build enforces the license policy declared at the top of
`manifest.yml`:

* **OFL-compatible donors** (`ofl_compatible_licenses`): glyphs are
  embedded without additional restrictions. Downstream users may
  use, modify, embed, and (re)sell under the standard OFL terms.

* **Donors accepted with extra conditions**
  (`accepted_with_conditions`): glyphs are embedded, but the
  donor's terms (which may be more restrictive than OFL) survive
  into the output font. The build propagates these extra terms to:
  - The output font's `name` table (OpenType `nameID 0` copyright
    notice and `nameID 13` license description)
  - The auto-generated `LICENSE-SOURCES.md` (per-codepoint
    licensing, so downstream users can filter / strip restricted
    glyphs programmatically)
  - The shipped README and `references/input-fonts/ATTRIBUTIONS.md`

* **Anything else** (proprietary, ambiguous, or undeclared): the
  build refuses to use the donor.

`LICENSE-SOURCES.md` is auto-generated per release, listing every
donor's license + attribution plus the per-cp licensing map. It is
included alongside the final TTF in GitHub Releases.

For all upstream policy rationale see the comment block at the top
of `manifest.yml`.

### FSung-NC — concrete build behavior

The current entry in `accepted_with_conditions` is `FSung-NC` (F.G.
Wang's non-commercial share + use grant for Full-Sung). When the
build encounters a donor with `license: FSung-NC`, it does the
following:

1. **Reads the policy entry** from `accepted_with_conditions` to
   learn the `restriction`, `restriction_summary`, full `statement`,
   and the donor list under `applies_to`.

2. **Records the per-cp licensing** as it stitches. For each
   codepoint whose donor is in `applies_to`, the record
   `{ cp, donor, license: "FSung-NC", restriction: "no-commercial-use" }`
   is written into the in-memory licensing map.

3. **Writes the output font's `name` table**:
   - `nameID 0` (copyright): standard OFL copyright notice, plus
     "Portions Copyright 2026 F.G. Wang (FSung-derived glyphs).
     Used under F.G. Wang's non-commercial share + use grant."
   - `nameID 13` (license description): standard OFL text, plus the
     FSung-NC addendum below (transcribed verbatim from the policy
     entry's `statement` field — F.G. Wang's Chinese text).

   Addendum text (transcribed into `nameID 13`):

   > Composite license: portions of this font derived from Full-Sung
   > (Taiwan 全宋體) by F.G. Wang (https://fgwang.blogspot.com/) are
   > subject to additional restrictions. Academic research, educational
   > work, and personal reading are permitted; commercial use
   > (any form of commercial profit-making activity) is prohibited.
   > Full statement: 現將此成果無條件分享出來，樂見學術研究、教育工作、
   > 個人閱讀這方面的運用，但請勿用做任何形式的商業營利行為。希望「全
   > 宋體」這個大型字庫以及「部件檢索」這個檢字工具，能在漢字文化的整
   > 理、研究上幫上一點小忙。 To request commercial-use permission:
   > https://fgwang.blogspot.com/

4. **Writes `LICENSE-SOURCES.md`** alongside the TTF. Format:

   ```markdown
   ## FSung (Full-Sung) — Taiwan 全宋體 — by F.G. Wang

   - Author: F.G. Wang — https://fgwang.blogspot.com/
   - Initial style/sources: Taiwan MOE (教育部)
   - License: FSung-NC (custom non-commercial share + use grant)
   - Restriction: **no commercial use**
   - Contact for commercial-use permission:
     https://fgwang.blogspot.com/

   ### Codepoints derived from FSung

   | Codepoint | Block | Donor file | sha256 |
   |---|---|---|---|
   | U+4E00 | CJK Unified Ideographs | references/input-fonts/FSung-m.ttf | 17f432a2cc07e38d9cea266c9cdb370c9021e7ca211e39801216daf1e355a271 |
   | U+20000 | CJK Unified Ideographs Extension B | references/input-fonts/FSung-2.ttf | 40296ae3899f17bf16976449fcbeadeb43e2c4d3e9f5ec6fd97438deb36d2ca4 |
   | ... | ... | ... | ... |
   ```

   The list of codepoints comes from walking ucode's per-cp
   manifest and filtering entries whose `source.label` is in
   `accepted_with_conditions[FSung-NC].applies_to`.

5. **Records the assignment in the build log** (stdout) for each
   restricted codepoint, so an operator running the build can see
   which glyphs will carry the FSung-NC restriction in the output.

Build acceptance for FSung-NC is: the output TTF + the shipped
`LICENSE-SOURCES.md` together carry enough information for a
downstream consumer (e.g., a packaging tool or preprocessor) to
identify and remove FSung-derived codepoints before commercial
distribution — without losing the rest of the font.

## Adding a new donor

1. Download the font to `sources/fonts/<filename>`
2. Compute sha256: `shasum -a 256 sources/fonts/<filename>`
3. Add an entry to `manifest.yml`
4. Re-run ucode's universal-set build to record per-cp coverage
   for the new donor
5. Test the build: `ruby scripts/stitch.rb`
