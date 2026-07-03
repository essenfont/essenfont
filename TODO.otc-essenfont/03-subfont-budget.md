# 03 — Subfont Budget

## The cap

`maxp` (Maximum Profile) table version 1.0 stores `numGlyphs` in a
**uint16** field — maximum value **65,535**. This is a hard format
limit for both TTF (`glyf`+`loca`) and OTF (`CFF`/`CFF2`) outlines.

fontisan's `Stitcher::GlyphLimit.check!` enforces this:

```ruby
# fontisan/lib/fontisan/stitcher/glyph_limit.rb (paraphrased)
def self.check!(count, format:)
  limit = 65_535
  return if count <= limit

  raise GlyphLimitExceededError,
        "#{format} subfont has #{count} glyphs; limit is #{limit}"
end
```

## Per-subfont accounting

For each subfont, the budget is:

```
budget = 65_535
  - 1 (reserved for .notdef at gid 0)
  - safety_margin (default: 50)  # dedup misses, compound glyphs expanding
  = 65_484
```

The safety margin covers:

- **Compound glyph expansion.** A donor's compound (composite) glyph
  may flatten into multiple simple glyphs when copied by the
  Stitcher. fontisan's `flatten-compound-glyphs` fix (commit 73820f1)
  is now conservative; rare cases still expand.
- **Dedup misses.** The Stitcher's `Deduplicator` uses a glyph
  signature hash. Hash collisions or near-identical glyphs (e.g.,
   NotoSansKR vs NotoSansJP Kana) bypass dedup.
- **.notdef variants.** Some donors ship a non-trivial `.notdef`
  glyph (Noto Last Resort); the Stitcher copies it per-subfont if
  dedup misses.

The 50-glyph margin is empirical — bumping to 200 if any subfont
encroaches.

## Per-plane projection (Unicode 17)

| Plane | Assigned cps | With backfill | Budget | Headroom |
|-------|--------------|---------------|--------|----------|
| 0     | ~62,000      | ~62,060       | 65,484 | ~3,400   |
| 1     | ~9,000       | ~9,000        | 65,484 | ~56,000  |
| 2     | ~60,000      | ~60,000       | 65,484 | ~5,400   |
| 3     | ~6,000       | ~6,000        | 65,484 | ~59,000  |
| 14    | ~100         | ~100          | 65,484 | ~65,300  |

All planes fit comfortably. The block sub-split (see
`02-plane-partition-strategy.md`) is dormant; it activates only if
a plane's assigned count exceeds `65,484`.

## Validation

After assembling each partition, but before calling the Stitcher,
`Essenfont::Otc::Build` checks:

```ruby
partition = blueprint.partition_for(:plane_0)
if partition.glyph_count_est > MAX_SUBFONT_GLYPHS
  raise SubfontBudgetExceededError, ...
end
```

`glyph_count_est` is an upper bound (cps + 1 for .notdef). The
actual count after Stitcher dedup is lower or equal.

After compilation, the build also verifies each emitted subfont:

```ruby
fonts.size.times do |i|
  face = Fontisan::FontLoader.load(otc_path, font_index: i)
  count = face.table("maxp").num_glyphs
  raise "subfont #{i} has #{count} glyphs (cap 65,535)" if count > 65_535
end
```

This post-write check catches any expansion the pre-write estimate
missed.

## What happens if a plane overflows

If the BMP, in a future Unicode version, exceeds 65,484 assigned
characters (unlikely before Unicode 25+), the partitioner splits
the plane into `:plane_0_a`, `:plane_0_b` by Unicode block. The
block boundary order is fixed in
`Essenfont::Otc::BlockCatalog::BMP_ORDER`, so the split is
reproducible across builds.

Today, this path is exercised only by a unit test
(`spec/essenfont/otc/plane_partitioner_overflow_spec.rb`) that
synthesizes an oversized plane.

## Donor count vs codepoint count

The 65,535 cap is on *glyphs in the output font*, not on input
codepoints. The Stitcher's `Deduplicator` collapses identical
glyphs (e.g., `.notdef` from 30 donors → 1 glyph).

So a partition of 62,000 codepoints may end up with 50,000 glyphs
after dedup. The pre-write estimate uses codepoint count (worst
case: 1 glyph per cp); the post-write check uses actual
`maxp.num_glyphs`.

## Summary

- Cap: 65,535 glyphs per subfont.
- Reservation: gid 0 = `.notdef`.
- Working budget: 65,484 (cap − 1 − 50 safety margin).
- All Unicode 17 planes fit with >3,000 glyphs headroom.
- Sub-split algorithm is dormant today, ready for future Unicode
  versions.
- Both pre-write (estimate) and post-write (actual) checks run on
  every build.
