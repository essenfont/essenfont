# Debugging a glyph

## Symptoms

- A glyph renders as tofu (□) or invisible
- A glyph overflows its em-box (extends past ascent/descent)
- A glyph renders at the wrong size (too large / too small)
- A glyph renders in the wrong style (looks like a different font)

## Step 1: Find the donor

```bash
bundle exec ruby -e '
  require "essenfont"
  manifest = Essenfont::Manifest.load
  donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
  cp_map = Essenfont::CpMap.from_donors(donors)
  info = cp_map[0x13080]  # replace with your codepoint
  puts info.inspect
  # => {:label=>"uni-hieroglyphica", :gid=>1234}
'
```

The `:label` tells you which donor owns this codepoint in the build.

## Step 2: Check if the donor has the glyph

```bash
bundle exec ruby -e '
  require "essenfont"
  require "fontisan"
  manifest = Essenfont::Manifest.load
  entry = manifest.find("uni-hieroglyphica")  # replace label
  font = Fontisan::FontLoader.load(entry.file)
  cmap = font.table("cmap")
  gid = cmap.unicode_mappings[0x13080]
  puts "donor gid: #{gid}"
  puts "donor has glyph: #{!gid.nil?}"
'
```

If `gid` is nil, the donor's cmap doesn't cover this codepoint.
The CpMap must have assigned it from a different donor (check
CpMap first-wins order in the manifest).

## Step 3: Dump the donor UFO

After UFO conversion + normalization, you can inspect the UFO:

```bash
bundle exec ruby -e '
  require "essenfont"
  require "fontisan"
  manifest = Essenfont::Manifest.load
  entry = manifest.find("uni-hieroglyphica")
  font = Fontisan::FontLoader.load(entry.file)
  ufo = Fontisan::Ufo::Convert::FromBinData.convert(font)
  Essenfont::Ufo::Normalization.apply!(ufo, target_upm: 1000)

  # Write the UFO to disk for FontForge inspection
  Fontisan::Ufo::Writer.write(ufo, "references/ufo-debug/uni-hieroglyphica.ufo")
  puts "wrote references/ufo-debug/uni-hieroglyphica.ufo"
'
```

Open in FontForge:

```bash
fontforge references/ufo-debug/uni-hieroglyphica.ufo
```

## Step 4: Check face metrics

After build, check each face's vertical metrics:

```bash
bundle exec ruby scripts/dump_face_metrics.rb Essenfont-Regular.ttc
```

Expected output (after v0.2.9 MetricsPass):
```
Face 0 (BMP): upm=1000 asc=800  desc=-200  yMax=820
Face 1 (SMP): upm=1000 asc=950  desc=-300  yMax=950
Face 2 (SIP): upm=1000 asc=920  desc=-220  yMax=950
Face 3 (TIP): upm=1000 asc=920  desc=-220  yMax=950
Face 4 (SSP): upm=1000 asc=800  desc=-200  yMax=800
```

If any face has `yMax > 1200`, MetricsPass may not have run or the
UFO normalization may not have scaled correctly.

## Step 5: Compare donor vs output glyph

Export both as SVG for side-by-side comparison:

```bash
bundle exec ruby -e '
  require "essenfont"
  require "fontisan"

  # Donor glyph
  manifest = Essenfont::Manifest.load
  entry = manifest.find("uni-hieroglyphica")
  font = Fontisan::FontLoader.load(entry.file)
  cmap = font.table("cmap")
  gid = cmap.unicode_mappings[0x13080]
  glyph = font.table("glyf").glyph_for(gid, font.table("loca"), font.table("head"))

  # Output glyph
  output = Fontisan::FontLoader.load("Essenfont-Regular.ttc", font_index: 1)
  out_cmap = output.table("cmap")
  out_gid = out_cmap.unicode_mappings[0x13080]
  out_glyph = output.table("glyf").glyph_for(out_gid, output.table("loca"), output.table("head"))

  puts "donor bbox:  xMin=#{glyph.xMin} yMin=#{glyph.yMin} xMax=#{glyph.xMax} yMax=#{glyph.yMax}"
  puts "output bbox: xMin=#{out_glyph.xMin} yMin=#{out_glyph.yMin} xMax=#{out_glyph.xMax} yMax=#{out_glyph.yMax}"

  scale = 1000.0 / font.table("head").units_per_em
  puts "expected (donor × #{scale.round(4)}): xMin=#{(glyph.xMin * scale).round} yMin=#{(glyph.yMin * scale).round} xMax=#{(glyph.xMax * scale).round} yMax=#{(glyph.yMax * scale).round}"
'
```

If the output bbox doesn't match the expected (donor × scale),
either normalization didn't apply or MetricsPass modified the
metrics after stitch (expected for face-level metrics, not per-glyph).

## Step 6: Check CpMap ordering

If the wrong donor owns a codepoint:

```bash
bundle exec ruby -e '
  require "essenfont"
  manifest = Essenfont::Manifest.load
  donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
  cp_map = Essenfont::CpMap.from_donors(donors)

  # Which donors COULD cover this codepoint?
  cp = 0x13080
  donors.each do |label, d|
    coverage = d[:coverage] || {}
    puts "#{label}: covers U+#{cp.to_s(16).upcase}? #{coverage.key?(cp)}"
  end
'
```

CpMap uses first-wins by manifest order. If a donor earlier in the
manifest covers the codepoint, it claims it before later donors.
Reorder manifest entries or adjust `covers:` / `restrict_to_covers:`
to change ownership.
