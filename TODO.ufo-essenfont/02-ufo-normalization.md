# 02 — UFO Normalization module

## Purpose

`Essenfont::Ufo::Normalization` scales a `Fontisan::Ufo::Font`'s
coordinates from the donor's native `unitsPerEm` to a target UPM
(1000). Per-donor uniform scaling preserves the donor's internal
proportions — every glyph from the same donor gets the same scale
factor, so the donor's design system stays coherent.

## API

```ruby
module Essenfont
  module Ufo
    class Normalization
      DEFAULT_TARGET_UPM = 1000

      attr_reader :target_upm, :source_upm, :scale_factor

      # @param ufo [Fontisan::Ufo::Font] the donor UFO to normalize
      # @param target_upm [Integer] desired unitsPerEm (default 1000)
      def initialize(ufo, target_upm: DEFAULT_TARGET_UPM); end

      # True when source UPM == target UPM (no-op optimization)
      def identity?; end

      # Scale the UFO's glyph coordinates + advance widths in-place.
      # @return [Fontisan::Ufo::Font] the same UFO, mutated
      def apply!; end

      # Class-level convenience: normalize and return the UFO
      def self.apply!(ufo, target_upm: DEFAULT_TARGET_UPM); end
    end
  end
end
```

## What gets scaled

| Artifact | Scaled? | How |
|----------|---------|-----|
| Glyph contour points (x, y) | YES | `(v * scale).round` per point |
| Glyph advance width | YES | `(w * scale).round` |
| `fontinfo.unitsPerEm` | YES | set to `target_upm` |
| `fontinfo.ascender/descender` | DEFERRED | UFO info fields — future release |
| Kerning pairs | DEFERRED | `kerning.plist` — future release |
| Anchors | DEFERRED | per-glyph `<anchor>` — future release |
| Vertical metrics (VOrg) | DEFERRED | future release |

v0.2.9 scales glyph outlines + widths + UPM only. This fixes the
glyph-bounds bug. Kerning/features defer to v0.3.0.

## fontisan UFO API constraints

- `Ufo::Glyph`: `attr_accessor :width` (mutable); `attr_reader :contours`
  (array reference — can mutate the array's contents)
- `Ufo::Point`: `attr_reader :x, :y` (**immutable** — must create new Point)
- `Ufo::Info`: `attr_accessor(*STANDARD_FIELDS)` includes `units_per_em`

Since points are immutable, normalization reconstructs each contour
with new `Point` objects. The contour is replaced in the glyph's
`@contours` array (mutable via reference).

## Design: strategy pattern for rounding

```ruby
module Essenfont
  module Ufo
    class Normalization
      class Rounding
        def call(value); end
      end

      class RoundHalfUp < Rounding
        def call(value) = value.round
      end

      class RoundHalfEven < Rounding  # Banker's rounding
        def call(value)
          value.round(half: :even)
        end
      end
    end
  end
end
```

Default: `RoundHalfUp`. OCP: adding a new rounding strategy = new
class, not editing existing code.

## File layout

```
lib/essenfont/ufo.rb                      ← namespace file (autoloads)
lib/essenfont/ufo/normalization.rb        ← Normalization class
lib/essenfont/ufo/normalization/          ← strategy classes (future)
  rounding.rb
```

## Acceptance criteria

- [ ] 2048-upm donor → scale 0.4883 → output UPM = 1000
- [ ] 1024-upm donor → scale 0.9766 → output UPM = 1000
- [ ] 1000-upm donor → scale 1.0 → `identity?` returns true, no mutation
- [ ] All glyph points scaled by exactly `scale_factor`
- [ ] Advance widths scaled by exactly `scale_factor`
- [ ] `fontinfo.units_per_em` set to `target_upm` after `apply!`
- [ ] Original glyph contours are not referenced after normalization (deep copy of points)
