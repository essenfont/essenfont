#!/usr/bin/env ruby
# frozen_string_literal: true

# Build Essenfont from donor fonts.
#
# Usage:
#   ruby scripts/build.rb                    # builds Essenfont-Regular.ttf
#   ruby scripts/build.rb --format=otf       # builds Essenfont-Regular.otf
#   ruby scripts/build.rb --format=all       # builds TTF + OTF
#
# The build:
# 1. Reads sources/manifest.yml → donor font registry
# 2. Loads each donor via Fontisan::FontLoader.load
# 3. Scans each donor's cmap → per-codepoint coverage
# 4. For each codepoint: extracts glyph from the first covering donor
# 5. Stitches all glyphs via Fontisan::Stitcher
# 6. Writes output in the requested format(s)

require "optparse"
require "yaml"
require "json"
require "fileutils"
require "digest"
require "fontisan"

module EssenfontBuild
  MANIFEST_PATH = File.expand_path("../sources/manifest.yml", __dir__)
  DONOR_DIR = File.expand_path("../references/input-fonts", __dir__)
  REMAP_DIR = File.expand_path("../sources/remaps", __dir__)
  OUTPUT_DIR = File.expand_path("..", __dir__)
  UCODE_MANIFEST = ENV.fetch("UCODE_MANIFEST", nil)
  UCODE_BLOCKS_PATH = "/Users/mulgogi/src/fontist/ucode/output/blocks/index.json"

  # Load all Unicode 17 block ranges from ucode's canonical blocks
  # index. Falls back to an inline subset if ucode isn't available
  # locally. Used by the coverage-validation gate to compute "% of
  # declared block present in donor cmap" — must cover every block
  # id referenced by manifest covers: declarations.
  def self.load_unicode_blocks
    if File.exist?(UCODE_BLOCKS_PATH)
      data = JSON.parse(File.read(UCODE_BLOCKS_PATH))
      data.each_with_object({}) do |b, h|
        h[b["id"]] = [b["first_cp"], b["last_cp"]]
      end
    else
      warn "WARN: ucode blocks/index.json not found at #{UCODE_BLOCKS_PATH}; using inline fallback"
      INLINE_UNICODE_BLOCKS
    end
  end

  INLINE_UNICODE_BLOCKS = {
    "Basic_Latin" => [0x0000, 0x007F],
    "CJK_Unified_Ideographs" => [0x4E00, 0x9FFF],
    "Tangut" => [0x17000, 0x187FF],
    "Tolong_Siki" => [0x11DB0, 0x11DEF],
    "Tai_Yo" => [0x1E6C0, 0x1E6FF],
    "Sidetic" => [0x10940, 0x1095F],
    "Beria_Erfe" => [0x16EA0, 0x16EDF],
    "Egyptian_Hieroglyphs" => [0x13000, 0x1342F],
    "Egyptian_Hieroglyphs_Extended_A" => [0x13460, 0x143FF],
    "Emoticons" => [0x1F600, 0x1F64F],
  }.freeze

  # Unicode 17.0 block ranges for blocks declared in the manifest.
  # Used by the coverage-validation gate to compute "% of declared
  # block actually present in donor cmap". Loaded from ucode/output/
  # blocks/index.json (canonical UCD data) at boot time.
  UNICODE_BLOCKS = load_unicode_blocks.freeze

  # Parse the donor manifest and load each available donor.
  # @return [Hash<Symbol, {font:, label:, file:, coverage:}>]
  def self.load_donors
    manifest = YAML.safe_load(File.read(MANIFEST_PATH))
    donors = manifest["donors"] || []
    loaded = {}

    donors.each do |entry|
      label = entry["label"].to_sym

      if entry["enabled"] == false
        warn "skip: donor #{label} is disabled (enabled: false in manifest)"
        next
      end

      # code_chart donors are synthetic; they don't have a real file
      # until fetch_chart_glyphs.rb runs. If the synthetic TTF is
      # missing, skip with a helpful pointer rather than failing.
      if entry["type"] == "code_chart"
        generated_dir = File.expand_path("../references/input-fonts/.generated", __dir__)
        synthetic = File.join(generated_dir, "#{entry["block"].tr("-", "_")}.ttf")
        if File.exist?(synthetic)
          entry = entry.merge("file" => synthetic)
        else
          warn "skip: code_chart donor #{label} — synthetic TTF not yet generated"
          warn "       run `bundle exec ruby scripts/fetch_chart_glyphs.rb` first"
          next
        end
      end

      file = entry["file"]
      path = resolve_donor_path(file)

      unless path && File.exist?(path)
        warn "skip: donor #{label} not found at #{file}"
        next
      end

      unless verify_font_file(path)
        warn "skip: donor #{label} is not a valid font file (likely a failed download)"
        next
      end

      unless verify_sha256(path, entry["sha256"], label)
        warn "skip: donor #{label} sha256 mismatch"
        next
      end

      if entry["codepoint_remap"]
        remap_path = resolve_remap_path(entry["codepoint_remap"])
        unless remap_path && File.exist?(remap_path)
          warn "skip: donor #{label} declares codepoint_remap at #{entry["codepoint_remap"]} but file not found"
          next
        end
        remap_data = YAML.safe_load(File.read(remap_path))
        mappings = remap_data["mappings"] || []
        if mappings.empty?
          warn "skip: donor #{label} codepoint_remap has no mappings yet (TODO.full/02 or 03)"
          next
        end
        remap = mappings.each_with_object({}) do |m, h|
          h[m["from"]] = m["to"]
        end
      end

      print "  loading #{label} (#{File.basename(path)})... "
      font_index = entry["font_index"] || 0
      begin
        font = Fontisan::FontLoader.load(path, font_index: font_index)
      rescue StandardError => e
        warn "skip: #{e.message}"
        next
      end
      raw_coverage = scan_cmap(font)
      if remap
        original_size = raw_coverage.size
        # Compute remapped coverage first (raw_coverage is a reference
        # to the cmap's hash; once we mutate it below, we can't read
        # the original cps anymore).
        coverage = apply_remap(raw_coverage, remap)
        # Now mutate the donor's cmap in-memory so the Stitcher sees
        # target Unicode codepoints when looking up glyphs. The
        # unicode_mappings hash is cached on the cmap table object,
        # so this mutation persists across the Stitcher's later reads.
        mutate_cmap_with_remap!(font, remap)
        puts "#{original_size} → #{coverage.size} codepoints (remapped)"
      else
        coverage = raw_coverage
        puts "#{coverage.size} codepoints"
      end
      loaded[label] = {
        font: font,
        label: label,
        file: path,
        coverage: coverage,
        covers: entry["covers"] || [],
      }
    end

    loaded
  end

  # Mutate the donor's cmap in-memory: for each (source_cp → target_cp)
  # in the remap, move the gid from source_cp to target_cp. cps not in
  # the remap are removed (we only want the donor's remapped coverage
  # in the output font, not its original ASCII/PUA positions).
  def self.mutate_cmap_with_remap!(font, remap)
    cmap = font.table("cmap")
    return unless cmap

    maps = cmap.unicode_mappings
    return unless maps

    new_maps = {}
    remap.each do |src, target|
      gid = maps[src]
      new_maps[target] = gid if gid
    end
    maps.replace(new_maps)
  end

  # Rewrite a cmap's codepoints using a remap table.
  # The donor's cmap is at "source" codepoints (e.g., ASCII for Kelly
  # Tolong, PUA for NotoSerifTaiYo); this maps each entry to its
  # target Unicode codepoint. Source cps without a remap entry are
  # dropped (the donor's other coverage isn't useful for essenfont).
  # @param cmap [Hash<Integer, Integer>] {source_cp → gid}
  # @param remap [Hash<Integer, Integer>] {source_cp → target_cp}
  # @return [Hash<Integer, Integer>] {target_cp → gid}
  def self.apply_remap(cmap, remap)
    remap.each_with_object({}) do |(src, target), h|
      gid = cmap[src]
      h[target] = gid if gid
    end
  end

  # Compute SHA256 of file and compare to expected.
  # Expected may be nil or "TBD" (unverified, warn but pass).
  # @return [Boolean] true if matches or unverified; false if mismatch.
  def self.verify_sha256(path, expected, label)
    return true if expected.nil? || expected == "TBD"

    actual = Digest::SHA256.file(path).hexdigest
    if actual == expected.downcase
      true
    else
      warn "    sha256 mismatch for #{label}:"
      warn "      expected: #{expected}"
      warn "      actual:   #{actual}"
      false
    end
  end

  # Validate that each declared `covers:` block has cmap coverage.
  # @param donors [Hash] loaded donors (post-cmap scan)
  # @return [Array<String>] list of failures; empty if all pass.
  def self.validate_coverage_gates(donors)
    failures = []
    donors.each_value do |d|
      covers = d[:covers] || []
      covers.each do |block|
        range = UNICODE_BLOCKS[block]
        unless range
          failures << "#{d[:label]}: unknown block '#{block}' in covers: (add to UNICODE_BLOCKS)"
          next
        end
        count = range_entry_count(d[:coverage], range)
        if count.zero?
          failures << "#{d[:label]}: declares covers:#{block} but cmap has 0 codepoints in #{format_range(range)}"
        end
      end
    end
    failures
  end

  # Count codepoints in `coverage` that fall within `range`.
  def self.range_entry_count(coverage, range)
    coverage.keys.count { |cp| cp >= range[0] && cp <= range[1] }
  end

  def self.format_range(range)
    "U+#{range[0].to_s(16).upcase}..U+#{range[1].to_s(16).upcase}"
  end

  def self.resolve_remap_path(specified)
    return specified if File.exist?(specified)
    File.join(REMAP_DIR, File.basename(specified))
  end

  # Verify that a file is actually a font (not an HTML error page).
  # @return [Boolean]
  def self.verify_font_file(path)
    return false unless File.exist?(path) && File.size(path) > 16

    magic = File.binread(path, 4)
    valid = [
      "\x00\x01\x00\x00", # TTF
      "OTTO",              # OTF (CFF)
      "true",              # TrueType (Apple variant)
      "ttcf",              # TTC
      "wOFF",              # WOFF
      "wOF2",              # WOFF2
      "\x00\x01\x00\x00".b # TTF (binary)
    ]
    return true if valid.include?(magic)

    # Check for Type 1 fonts
    first_byte = magic.getbyte(0)
    return true if first_byte == 0x80 # PFB

    warn "    first 4 bytes: #{magic.inspect} — not a font magic"
    false
  rescue StandardError
    false
  end

  # Resolve a donor file path relative to the donor directory.
  def self.resolve_donor_path(file)
    return file if File.exist?(file)

    candidate = File.join(DONOR_DIR, File.basename(file))
    return candidate if File.exist?(candidate)

    nil
  end

  # Scan a font's cmap for Unicode coverage.
  # @return [Hash<Integer, Integer>] {codepoint → gid}
  def self.scan_cmap(font)
    cmap = font.table("cmap")
    return {} unless cmap

    mappings = cmap.unicode_mappings || {}
    # If this is a TTC face, the cmap might be on the inner font
    mappings
  rescue StandardError
    {}
  end

  # Build a per-codepoint donor selection map.
  # For each codepoint covered by ANY donor, pick the first donor
  # (in manifest order) that covers it.
  # @param donors [Hash] loaded donors
  # @return [Hash<Integer, {label:, gid:}>]
  def self.build_codepoint_map(donors)
    all_cps = Set.new
    donors.each_value { |d| all_cps.merge(d[:coverage].keys) }

    puts "  total codepoints across all donors: #{all_cps.size}"

    cp_map = {}
    all_cps.sort.each do |cp|
      donors.each_value do |d|
        gid = d[:coverage][cp]
        if gid
          cp_map[cp] = { label: d[:label], gid: gid }
          break
        end
      end
    end

    puts "  codepoints assigned to a donor: #{cp_map.size}"
    cp_map
  end

  # If ucode's universal-set manifest exists, use it to drive the
  # per-cp mapping instead of scanning cmaps. This gives us exact
  # donor provenance per codepoint.
  # @return [Hash, nil] the manifest entries or nil if not found
  def self.load_ucode_manifest
    return nil unless UCODE_MANIFEST && File.exist?(UCODE_MANIFEST)

    data = JSON.parse(File.read(UCODE_MANIFEST))
    entries = data["entries"] || []
    return nil if entries.empty?

    puts "  using ucode universal-set manifest (#{entries.size} entries)"
    entries
  end

  # Build the font.
  # @param format [Symbol] :ttf, :otf, or :all
  def self.run(format: :ttf)
    puts "=== Essenfont build (format: #{format}) ==="

    donors = load_donors
    if donors.empty?
      warn "ERROR: no donor fonts loaded. Check sources/manifest.yml + references/input-fonts/"
      exit 1
    end

    coverage_failures = validate_coverage_gates(donors)
    unless coverage_failures.empty?
      warn "ERROR: coverage-validation gate failed (declared covers: blocks have 0 cmap coverage):"
      coverage_failures.each { |f| warn "  - #{f}" }
      warn ""
      warn "Fix the manifest's covers: declarations to match actual donor cmap coverage."
      exit 1
    end

    cp_map = build_codepoint_map(donors)
    if cp_map.empty?
      warn "ERROR: no codepoints covered by any donor"
      exit 1
    end

    # Build the stitched font
    puts "=== Stitching #{cp_map.size} glyphs ==="
    stitcher = Fontisan::Stitcher.new

    # Register all donors with the stitcher
    donors.each_value do |d|
      stitcher.add_source(d[:label], d[:font])
    end

    # Include .notdef from the first donor
    first_label = donors.values.first[:label]
    stitcher.include_notdef(from: first_label)

    # Include each codepoint
    cp_count = 0
    cp_map.each_slice(1000) do |slice|
      slice.each do |cp, info|
        stitcher.include_codepoints([cp], from: info[:label])
      end
      cp_count += slice.size
      print "\r  #{cp_count}/#{cp_map.size} codepoints stitched"
    end
    puts

    # Write outputs
    formats = format == :all ? %i[ttf otf] : [format.to_sym]
    formats.each do |fmt|
      ext = fmt == :otf ? "otf" : "ttf"
      output_path = File.join(OUTPUT_DIR, "Essenfont-Regular.#{ext}")
      puts "=== Writing #{output_path} ==="
      stitcher.write_to(output_path, format: fmt)
      validate_and_repair_cmap(output_path)
      puts "  #{output_path} (#{File.size(output_path)} bytes)"
    end
  end

  # Validate that every cmap entry points to a valid gid. If not,
  # rebuild the cmap with only valid entries and rewrite the font.
  #
  # This fixes the issue where the Stitcher's glyph ordering doesn't
  # perfectly match the cmap's gid references, causing Safari to
  # reject the font.
  def self.validate_and_repair_cmap(path)
    font = Fontisan::FontLoader.load(path)
    maxp = font.table("maxp")
    num_glyphs = maxp&.num_glyphs || 0

    cmap = font.table("cmap")
    mappings = cmap&.unicode_mappings || {}

    valid = {}
    invalid_count = 0
    mappings.each do |cp, gid|
      if gid < num_glyphs
        valid[cp] = gid
      else
        invalid_count += 1
      end
    end

    if invalid_count.positive?
      puts "  repairing: #{invalid_count} cmap entries pointed to non-existent gids (max gid = #{num_glyphs - 1})"

      # Read all table bytes
      tables = {}
      font.table_names.each do |tag|
        raw = begin
                font.table(tag)&.raw_data
              rescue StandardError
                nil
              end
        tables[tag] = raw if raw
      end

      # Build cleaned cmap from valid mappings only
      glyphs_for_cmap = Array.new(num_glyphs) do |i|
        Fontisan::Ufo::Glyph.new(name: i.zero? ? ".notdef" : "gid#{i}")
      end
      valid.each_value do |gid|
        next if gid >= glyphs_for_cmap.size
      end
      valid.each do |cp, gid|
        glyphs_for_cmap[gid]&.add_unicode(cp)
      end
      tables["cmap"] = Fontisan::Ufo::Compile::Cmap.build(nil, glyphs: glyphs_for_cmap)

      sfnt = tables.key?("CFF ") ? 0x4F54544F : 0x00010000
      Fontisan::FontWriter.write_to_file(tables, path, sfnt_version: sfnt)
      puts "  repaired: #{valid.size} valid cmap entries retained"
    else
      puts "  cmap validation: all #{valid.size} entries valid"
    end
  rescue StandardError => e
    warn "  WARNING: cmap validation failed: #{e.message}"
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { format: :ttf }
  OptionParser.new do |opts|
    opts.banner = "Usage: build.rb [options]"
    opts.on("--format=FORMAT", "ttf, otf, or all (default: ttf)") { |v| options[:format] = v.to_sym }
  end.parse!

  EssenfontBuild.run(format: options[:format])
end
