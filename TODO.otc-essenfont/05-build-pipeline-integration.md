# 05 — Build Pipeline Integration

## Current state

`scripts/build.rb` runs this pipeline today:

1. `load_donors` — read `sources/manifest.yml`, open each donor via
   `Fontisan::FontLoader.load`, scan its cmap.
2. `build_codepoint_map(donors)` — produce `cp_map`:
   `{cp => {label:, gid:}}`. Filters PUA/Surrogate/Specials.
   Backfills Cc/Cf control cps as gid 0 from the first donor.
3. Stitch all codepoints into ONE Stitcher session with the OLD API
   (`include_codepoints([cp], from: label)` — no `into:`).
4. `stitcher.write_to(output_path, format: fmt)` — single TTF or OTF.
5. `validate_and_repair_cmap(path)` — drop cmap entries pointing to
   gids ≥ `maxp.num_glyphs`.

The OLD API defaults to the `:main` subfont. With one subfont and
~131k glyphs, step 4 hits the cap, and step 5 drops ~3,000 entries.

## Target state

The same load + cp_map logic, but:

- The Stitcher session uses the NEW `into:` API.
- The partitioner (default: `PlanePartitioner`) decides which
  subfont each cp lands in.
- The Writer emits `Essenfont-Regular.otc` (default), or per-plane
  TTFs with `--format=ttf-per-plane`, or the legacy single TTF
  with `--format=ttf` (kept for backward compatibility).

## CLI flags

```
ruby scripts/build.rb                       # default: --format=otc
ruby scripts/build.rb --format=otc          # explicit OTC
ruby scripts/build.rb --format=ttf          # legacy: BMP-only single TTF
ruby scripts/build.rb --format=ttf-per-plane  # per-plane TTF set
ruby scripts/build.rb --format=otf          # legacy single OTF (cap-bounded)
ruby scripts/build.rb --partitioner=plane   # default; reserved for future partitioners
```

`--format=otc` becomes the default. The previous default (`ttf`)
remains available.

## Code changes

### Top of `scripts/build.rb`

```ruby
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "essenfont"   # triggers autoload of Essenfont::Otc
```

### `EssenfontBuild.run` (rewritten high-level)

```ruby
def self.run(format: :otc, partitioner: :plane)
  puts "=== Essenfont build (format: #{format}) ==="

  donors = load_donors
  # ... validation unchanged ...

  cp_map = build_codepoint_map(donors)
  # ... unchanged ...

  case format
  when :otc
    build_otc(cp_map:, donors:, partitioner:)
  when :ttf_per_plane
    build_per_plane_ttfs(cp_map:, donors:, partitioner:)
  when :ttf, :otf
    build_legacy_single(cp_map:, donors:, format:)  # BMP-only, for compat
  else
    raise ArgumentError, "unknown format: #{format}"
  end
end
```

### `build_otc` (new)

```ruby
def self.build_otc(cp_map:, donors:, partitioner:)
  partitioner_klass = partitioner_for(partitioner)
  build = Essenfont::Otc::Build.new(
    cp_map:,
    donors:,
    partitioner: partitioner_klass.new,
    format: :ttf,                # subfont outline format
    collection_format: :otc      # container format
  )
  output_path = File.join(OUTPUT_DIR, "Essenfont-Regular.otc")
  result = build.call(output_path:)

  puts "=== Wrote #{output_path} (#{result[:bytes]} bytes) ==="
  result[:subfonts].each do |sf|
    puts "  #{sf[:name]}: #{sf[:glyph_count]} glyphs, #{sf[:codepoint_count]} codepoints"
  end

  validate_otc!(output_path, expected_subfonts: result[:subfonts].size)
end
```

### `validate_otc!` (new)

```ruby
def self.validate_otc!(path, expected_subfonts:)
  face_count = count_faces(path)
  raise "OTC has #{face_count} faces, expected #{expected_subfonts}" if
    face_count != expected_subfonts

  expected_subfonts.times do |i|
    face = Fontisan::FontLoader.load(path, font_index: i)
    count = face.table("maxp")&.num_glyphs || 0
    raise "face #{i} has #{count} glyphs (cap 65,535)" if count > 65_535
  end

  union = compute_cmap_union(path)
  if union.size < cp_map.size * 0.99
    raise "cmap union dropped #{cp_map.size - union.size} entries"
  end
end

def self.count_faces(path)
  # TTC header: 4 bytes "ttcf" + 2 bytes major + 2 bytes minor + 4 bytes count
  header = File.binread(path, 12)
  _tag, _maj, _min, count = header.unpack("a4 n n N")
  count
end
```

### `build_per_plane_ttfs` (new)

Same partition logic, but writes N TTFs instead of one OTC:

```ruby
def self.build_per_plane_ttfs(cp_map:, donors:, partitioner:)
  partitioner_klass = partitioner_for(partitioner)
  session = Essenfont::Otc::StitcherSession.new(
    donors:,
    blueprint: partitioner_klass.new.partition(cp_map)
  )
  stitcher = Fontisan::Stitcher.new
  donors.each_value { |d| stitcher.add_source(d[:label], d[:font]) }
  session.apply(stitcher)

  session.blueprint.each_partition do |partition|
    out = File.join(OUTPUT_DIR, "Essenfont-#{Naming.face_name(partition.name)}.ttf")
    stitcher.write_to(out, format: :ttf, subfont: partition.name)
    validate_and_repair_cmap(out)
  end
end
```

### `build_legacy_single` (existing path, simplified)

Keep the current single-TTF code path but **force `partition =
:plane_0`** so only BMP codepoints land in the output. Documents the
limitation up front:

```ruby
def self.build_legacy_single(cp_map:, donors:, format:)
  warn "INFO: legacy --format=#{format} emits BMP-only (Plane 0). " \
       "Use --format=otc for full Unicode coverage."
  bmp_map = cp_map.select { |cp, _| cp <= 0xFFFF }
  # ... existing stitch logic with bmp_map ...
end
```

### Removed

- `validate_and_repair_cmap(path)` — the post-write repair step is
  no longer needed because the OTC pipeline never exceeds the cap.
  (The function stays defined for the legacy TTF path; the OTC path
  does not call it.)

## Backwards compatibility

- `Essenfont-Regular.ttf` is still produced when `--format=ttf` is
  passed. But it's now BMP-only (~62k glyphs, well under cap).
- `Essenfont-Regular.otf` (legacy) still produced for `--format=otf`.
  Same cap behavior as legacy TTF.
- The GitHub Release artifact changes from `.ttf` to `.otc`. Users
  who pin to `.ttf` URLs need to switch to `.otc` or per-plane
  `.ttf` URLs. This is documented in the README and the release
  notes.

## ucode manifest integration

The build still loads `UCODE_MANIFEST` (env var) if present, to
drive per-cp donor provenance. The partitioner sees the same
`cp_map` shape regardless of manifest source. No changes needed.

## Coverage gate

`validate_coverage_gates(donors)` (declared `covers:` blocks have ≥1
cmap hit) runs *before* partitioning, unchanged. After
partitioning, the new `validate_otc!` runs a complementary check on
the union of subfont cmaps. Together they catch:

- Donor cmap drift (donor X lost coverage of block Y → first gate fires)
- Stitcher drops (cp X in cp_map but missing from any subfont cmap →
  second gate fires)

Both gates raise hard errors, not warnings. The build never silently
loses coverage.

## Performance

- Stitching 131k glyphs: ~6 min (current).
- OTC write adds ~30 s (Collection::Builder overhead for 5 fonts).
- Per-plane TTF write adds ~10 s × 5 = ~50 s.
- Total OTC build: ~7 min. Acceptable for a release artifact built
  in CI.

The pipeline is single-threaded. Multi-threading the per-partition
compile would save ~3 min but introduces fontisan state-safety
questions — out of scope.

## What this does NOT change

- `scripts/build-svg-donor.rb` — synthetic donor pipeline, unchanged.
- `scripts/verify.rb` — round-trip validation, unchanged (still
  takes a single font path; for OTC, accepts an optional
  `--font-index`).
- `sources/manifest.yml` — donor registry, unchanged.
- `references/input-fonts/` — donor binaries, unchanged.
- The C0/C1 + Cf backfill logic in `build_codepoint_map` — unchanged.
- The PUA / Surrogate / Specials filter — unchanged.
