# 07 — Specs

## New spec files

### `spec/essenfont/ufo/normalization_spec.rb`

```ruby
describe Essenfont::Ufo::Normalization do
  describe "#scale_factor" do
    it "returns 1.0 for a 1000-upm UFO"
    it "returns 0.9766 for a 1024-upm UFO"
    it "returns 0.4883 for a 2048-upm UFO"
    it "returns 0.4167 for a 2400-upm UFO"
  end

  describe "#identity?" do
    it "returns true when source UPM == target UPM"
    it "returns false when source UPM != target UPM"
  end

  describe "#apply!" do
    it "sets fontinfo.units_per_em to target UPM"
    it "scales all glyph contour points by scale_factor"
    it "scales all glyph advance widths by scale_factor"
    it "does not mutate the UFO when identity?"
    it "handles composite glyphs (components with transforms)"
    it "handles empty glyphs (.notdef only)"
  end
end
```

### `spec/essenfont/otc/metrics_pass_spec.rb`

```ruby
describe Essenfont::Otc::MetricsPass do
  describe "#recompute!" do
    it "patches head.xMin/yMin/xMax/yMax from glyph bbox union"
    it "patches hhea.ascent to max glyph yMax (≥ 800 floor)"
    it "patches hhea.descent to min glyph yMin (≤ -200 ceiling)"
    it "patches OS/2.sTypoAscender to match hhea.ascent"
    it "patches OS/2.usWinAscent (capped at 0xFFFF)"
    it "updates head.modified timestamp"
    it "round-trips through Fontisan::Collection::Reader"
  end
end
```

### `spec/essenfont/cp_map_spec.rb` — add new context

```ruby
describe Essenfont::CpMap, "restrict_to_covers enforcement" do
  it "does not assign Basic Latin to fsung-m"
  it "assigns Basic Latin to noto-sans"
  it "still assigns CJK Unified Ideographs to fsung-m"
end
```

## Test fixtures

- `spec/fixtures/fonts/test-1000.ttf` — minimal 1000-upm font with 2 glyphs
- `spec/fixtures/fonts/test-2048.ttf` — minimal 2048-upm font with 2 glyphs (same glyphs, 2× coords)
- `spec/fixtures/fonts/test-1024.ttf` — minimal 1024-upm font

Fixtures are committed; donors from references/input-fonts/ are
NOT used in unit specs (they're too large for CI).

## Acceptance criteria

- [ ] `bundle exec rspec` passes all new specs
- [ ] No existing specs regress
- [ ] Coverage ≥ 90% for new modules
