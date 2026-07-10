# 01 — CpMap coverage filter fix

## Problem

`Essenfont::CpMap.new_from_scan` (cp_map.rb:47-56) calls its own
`scan_cmap(d[:font])` which reads `cmap.unicode_mappings` from the
**raw font**, bypassing the `restrict_to_covers` filter that
`DonorLoader#scan_coverage` applies.

Result: FSung-m's full cmap (including Basic Latin, Cyrillic, etc.)
is fed into CpMap's first-wins assignment. FSung is loaded before
Noto Sans in manifest order, so FSung claims every codepoint its
cmap contains — including U+0041 (`A`).

## Fix

One behavioral change in `cp_map.rb:50`:

```ruby
# Before:
mappings = scan_cmap(d[:font])

# After:
mappings = d[:coverage] || scan_cmap(d[:font])
```

`d[:coverage]` is already set by `DonorLoader#load_one`
(donor_loader.rb:61) via `scan_coverage(font, entry:)`, which
applies the `restrict_to_covers` filter. CpMap just needs to
use it.

## Why this is correct

- `scan_coverage` (donor_loader.rb:126-139) already implements
  the correct filter: if `entry.restrict_to_covers?`, it intersects
  the cmap with the declared `covers:` block ranges.
- The filtered coverage is stored on the donor hash as `coverage:`.
- CpMap is the ONLY consumer that should decide codepoint ownership.
  By reading the filtered coverage, CpMap becomes the single
  enforcement point.
- The fallback `|| scan_cmap(d[:font])` covers test scenarios where
  a raw font hash (without `:coverage`) is passed.

## Acceptance criteria

- [ ] `CpMap.from_donors(donors)[0x41][:label]` is NOT `fsung-m`
- [ ] `CpMap.from_donors(donors)[0x41][:label]` IS `noto-sans`
- [ ] `CpMap.from_donors(donors)[0x4E00][:label]` IS `fsung-m` (CJK still from FSung)
- [ ] Existing cp_map_spec passes
- [ ] New spec: "respects restrict_to_covers on donor entries"
