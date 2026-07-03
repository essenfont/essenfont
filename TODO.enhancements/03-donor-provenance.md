# 03 — Donor Provenance Explorer

## Goal

Surface, for every codepoint, which donor font contributed its glyph.
Builds trust and differentiates essenfont from opaque bundled fonts.

## Why

Currently the donor attribution lives in `sources/manifest.yml` but
isn't exposed per-codepoint on the website. Users see "this glyph
rendered" but not "this glyph came from Noto Sans Egyptian
Hieroglyphs v2.003, GID 1240".

For type designers studying glyph variants, researchers comparing
donor provenance, and compliance teams tracking license obligations,
per-codepoint provenance is the killer data layer.

## Data flow

### Build emits provenance.json

New script: `scripts/emit_provenance_manifest.rb`

Input: `cp_map` (from `build.rb`) + donor metadata (from manifest.yml)

Output: `provenance.json` with structure:

```json
{
  "version": "0.2.0",
  "released_at": "2026-07-15T10:00:00Z",
  "donors": {
    "noto_sans_egyptian_hieroglyphs": {
      "label": "noto_sans_egyptian_hieroglyphs",
      "family": "Noto Sans Egyptian Hieroglyphs",
      "version": "2.003",
      "license": "OFL",
      "sha256": "abc123...",
      "url": "https://fonts.google.com/noto"
    },
    ...
  },
  "blocks": {
    "Egyptian_Hieroglyphs": {
      "primary_donor": "noto_sans_egyptian_hieroglyphs",
      "donors": ["noto_sans_egyptian_hieroglyphs", "unihieroglyphica"],
      "first_cp": "0x13000",
      "last_cp": "0x1342F"
    },
    ...
  },
  "codepoints": {
    "0x13000": { "donor": "noto_sans_egyptian_hieroglyphs", "gid": 1 },
    "0x13001": { "donor": "noto_sans_egyptian_hieroglyphs", "gid": 2 },
    ...
  }
}
```

The `codepoints` map is large (~131k entries) but compresses well —
ship as `provenance.json.gz` (~500 KB compressed) and decompress
on-demand at runtime.

### Website consumes provenance.json

- **UnicodeCharPage**: replaces the placeholder provenance section
  with real data: "Donor: Noto Sans Egyptian Hieroglyphs v2.003 ·
  GID 1240 · OFL · [donor detail →]"
- **UnicodeBlockPage**: shows the primary donor + contributor count
  for the block
- **New /provenance page**: global overview — heat map of which donor
  covers which blocks, click any block → block page

### /provenance page

Visual: matrix of donors × blocks, colored cell = primary contributor.

```
                  BMP    SMP    SIP    TIP    SSP
Noto Sans         ███    ██     ░      ░      ░
FSung             ░      ░      ███    ██     ░
UniHieroglyphica  ░      ██     ░      ░      ░
Lentariso         ░      ██     ░      ░      ░
...               ...
```

Each cell clickable → block page filtered to that donor.

Click a donor name → /donors/:slug page (already exists).

## Acceptance

- `scripts/emit_provenance_manifest.rb` produces provenance.json
- Release workflow uploads provenance.json alongside coverage.json
- Site CI downloads provenance.json into public/
- UnicodeCharPage shows real donor + gid for every codepoint
- UnicodeBlockPage shows primary + secondary donors for the block
- /provenance page visualizes the donor × block matrix
- "View donor source" link goes to the donor's repo/URL
