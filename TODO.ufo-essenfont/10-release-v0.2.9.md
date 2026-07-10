# 10 — Release v0.2.9

## Pre-release checklist

- [ ] All TODO 01-09 complete
- [ ] `bundle exec rspec` passes
- [ ] `scripts/verify.rb Essenfont-Regular.ttc` passes
- [ ] Visual spot-check: 𓂀 + Latin + CJK render correctly
- [ ] PR merged to main

## Release steps

### 1. Bump VERSION

```bash
cd /Users/mulgogi/src/essenfont/essenfont
# After PR merge, on main:
echo "0.2.9" > VERSION
git add VERSION
git commit -m "v0.2.9"
```

### 2. Tag

```bash
git tag v0.2.9
git push origin main
git push origin v0.2.9
```

### 3. release.yml fires (automatic)

The tag push triggers `.github/workflows/release.yml`:
- Sets up Ruby 3.4 + bundler-cache
- Fetches donor fonts (ucode fetch fonts)
- Downloads FSung files (Google Drive)
- `bundle exec ruby scripts/build.rb --format=ttc`
- `bundle exec ruby scripts/build.rb --format=ttf-per-plane`
- `bundle exec ruby scripts/encode-woff.rb` (×5 planes)
- `bundle exec ruby scripts/emit_coverage_manifest.rb`
- Uploads all artifacts to GH Release v0.2.9
- `npm publish essenfont@0.2.9`
- Fires `repository_dispatch` → essenfont.github.io

### 4. Website auto-updates (automatic)

The website's `site.yml` receives `repository_dispatch`:
- Downloads latest Essenfont-Regular.ttc
- Regenerates per-block WOFF2 subsets
- Runs `gen-site-stats.mjs` + new `gen-face-table.mjs` + `gen-donor-attribution.mjs`
- Astro build → GitHub Pages deploy

## Release notes (for GH Release body)

```
## Essenfont v0.2.9 — UFO-driven build + glyph-bounds fix

### Fixed
- **Glyph bounds overflow**: glyphs from non-1000-upm donors are now
  scaled to 1000-upm before stitching. Per-donor uniform scaling
  preserves each donor's internal proportions.
- **FSung scope leak**: `restrict_to_covers: true` is now enforced
  at CpMap construction time. FSung-m no longer claims Basic Latin.
- **Egyptian Hieroglyphs**: primary donor switched from egyptian-text
  (2048-upm, required scaling) to uni-hieroglyphica (1000-upm, native).

### Added
- `Essenfont::Ufo::Normalization` — per-donor UPM scaling at UFO layer
- `Essenfont::Otc::MetricsPass` — per-face vertical-metric recompute
  from actual glyph extents
- `docs/architecture.md`, `docs/adding-a-donor.md`, `docs/debugging.md`

### Changed
- Build pipeline now converts every donor TTF → UFO → normalize →
  stitch (previously: TTF → stitch directly)
- Per-face `head.bbox`, `hhea`, `OS/2` computed from actual glyphs
  (previously: frozen Latin profile on all faces)
```

## Acceptance criteria

- [ ] v0.2.9 tag pushed
- [ ] GH Release v0.2.9 published with all artifacts
- [ ] npm `essenfont@0.2.9` published
- [ ] Website deploys with v0.2.9 data within 10 minutes
