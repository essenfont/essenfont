# 09 — Build + verify

## Pre-build

```bash
cd /Users/mulgogi/src/essenfont/essenfont
git checkout fix/ufo-normalization-and-cpmap-filter
bundle install
bundle exec rspec                         # all specs pass
```

## Build

```bash
bundle exec ruby scripts/build.rb --format=ttc
```

Expected output: `Essenfont-Regular.ttc` at repo root.

## Verify

```bash
bundle exec ruby scripts/verify.rb Essenfont-Regular.ttc
```

Checks:
- head.unitsPerEm == 1000 per face
- glyph count ≤ 65,535 per face
- cmap union ≥ 99% of assigned Unicode 17
- MetricsPass ran (head.yMax matches glyph extents)

## Visual check

Export glyphs as SVG and render in browser:

```bash
bundle exec ruby scripts/dump_face_metrics.rb Essenfont-Regular.ttc
# Should show:
#   Face 0 (BMP):   upm=1000 asc=800  desc=-200 yMax≈820
#   Face 1 (SMP):   upm=1000 asc≈900  desc≈-300 yMax≈950   ← was 11160!
#   Face 2 (SIP):   upm=1000 asc≈920  desc≈-220 yMax≈950
#   Face 3 (TIP):   upm=1000 asc≈920  desc≈-220 yMax≈950
#   Face 4 (SSP):   upm=1000 asc=800  desc=-200 yMax≈800
```

Spot-check codepoints:

| Codepoint | Expected | How to verify |
|-----------|----------|---------------|
| U+0041 (A) | noto-sans, fits em-box | dump glyph bbox |
| U+4E00 (一) | fsung-m, scaled 0.9766, fits em-box | dump glyph bbox |
| U+13080 (𓂀) | uni-hieroglyphica, native 1000-upm, fits em-box | dump glyph bbox |

## Acceptance criteria

- [ ] Build completes without errors
- [ ] verify.rb passes all checks
- [ ] No face has `head.yMax > 1200`
- [ ] U+0041 donor is `noto-sans` (not `fsung-m`)
- [ ] U+13080 donor is `uni-hieroglyphica` (not `egyptian-text`)
- [ ] U+13080 glyph bbox in Essenfont ≤ ±500 (was ±942)
