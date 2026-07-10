# 08 — Architecture docs

## Location

`docs/` directory at repo root (NEW — does not exist yet).

## Files

### `docs/architecture.md`

The canonical reference for the codebase. Covers:

1. **What this repo builds** — one TTC with 5 faces (BMP/SMP/SIP/TIP/SSP)
2. **Repository layout** — lib/, scripts/, sources/, references/, spec/
3. **Build pipeline** — 7-stage flow diagram (manifest → load → normalize → CpMap → partition → stitch → metrics)
4. **Module guide** — per-module: responsibility, public API, key methods
5. **Design decisions**
   - Why UFO-driven (per-donor normalization, Noto workflow alignment, inspectability)
   - Why UPM=1000 (134/148 donors native, PostScript convention)
   - Why per-face metrics from actual glyphs (not frozen Latin profile)
   - Why restrict_to_covers enforced at CpMap layer
   - Why FSung for CJK (authoritative Traditional-first 全宋體)
   - Why uni-hieroglyphica for Egyptian (Suignard, upm=1000, no scaling)
6. **Data shapes** — CpMap, DonorHash, Partition
7. **Autoload convention** — how modules resolve (no require_relative)

### `docs/adding-a-donor.md`

Step-by-step guide:

1. Obtain the font file + verify license (OFL or accepted_with_conditions)
2. Compute sha256
3. Add entry to `sources/manifest.yml` (label, file, sha256, license, covers, restrict_to_covers)
4. Place font in `references/input-fonts/`
5. Run `bundle exec ruby scripts/build.rb --format=ttc`
6. Run `bundle exec ruby scripts/verify.rb Essenfont-Regular.ttc`
7. Check coverage: `bundle exec ruby -e 'puts Essenfont::CpMap.from_donors(...).size'`

### `docs/debugging.md`

How to investigate a glyph rendering issue:

1. Find the donor: `Essenfont::CpMap.from_donors(...)[cp]`
2. Dump the donor UFO: `bundle exec ruby scripts/dump_donor_ufo.rb <label>`
3. Open in FontForge: `fontforge references/ufo-debug/<label>.ufo`
4. Check face metrics: `bundle exec ruby scripts/dump_face_metrics.rb Essenfont-Regular.ttc`
5. Compare donor vs output glyph: export both as SVG

## Acceptance criteria

- [ ] `docs/architecture.md` exists with all 7 sections
- [ ] `docs/adding-a-donor.md` has runnable steps
- [ ] `docs/debugging.md` has runnable steps
- [ ] README.adoc links to docs/architecture.md
