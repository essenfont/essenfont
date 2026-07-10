# 04 — DonorLoader UFO conversion path

## Current flow (cp_map.rb bypasses filter)
```
Manifest → DonorLoader.load_one(entry) → {font:, coverage:, remap:, entry:}
                                              ↓
                       CpMap reads d[:font] raw cmap (BUG)
```

## New flow (UFO-driven)
```
Manifest → DonorLoader.load_one(entry)
             ├─ resolve path + verify sha256
             ├─ Fontisan::FontLoader.load(path)
             ├─ Fontisan::Ufo::Convert::FromBinData.convert(font) → UFO
             ├─ Essenfont::Ufo::Normalization.apply!(ufo, target_upm: 1000)
             ├─ filter_coverage(ufo, entry) → filtered cmap
             └─ return {label:, ufo:, coverage:, remap:, entry:}
                       ↓
           CpMap reads d[:coverage] (filtered, normalized UFO cmap)
                       ↓
           Otc::Build passes d[:ufo] to Stitcher.add_source
```

## Changes to `donor_loader.rb`

1. `load_one` gains a `convert_to_ufo` step after `load_font`
2. Returns `ufo:` instead of `font:` in the donor hash
3. `scan_coverage` reads from the UFO (which is already normalized)
4. CBDT-only donors (NotoColorEmoji) bypass UFO conversion (separate bitmap path)

## CBDT exemption

Donors with `bitmap_mode == :cbdt` have no glyf outlines. The
Stitcher propagates their CBDT/CBLC table bytes directly. UFO
conversion would lose this data. DonorLoader checks `bitmap_mode`
and skips UFO conversion for CBDT donors, returning the raw font.

## Acceptance criteria

- [ ] Every non-CBDT donor returns a `ufo:` key
- [ ] Every returned UFO has `units_per_em == 1000`
- [ ] `coverage:` respects `restrict_to_covers`
- [ ] CBDT donors still return `font:` for the Stitcher's CBDT path
- [ ] Build produces same glyph count as before (no coverage loss)
