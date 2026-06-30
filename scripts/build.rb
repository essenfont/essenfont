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

  # Unicode 17.0 block ranges for blocks declared in the manifest.
  # Used by the coverage-validation gate to compute "% of declared
  # block actually present in donor cmap". Temporary scaffolding
  # until ucode exports a canonical block-range lookup.
  UNICODE_BLOCKS = {
    "Basic_Latin" => [0x0000, 0x007F],
    "Latin-1_Supplement" => [0x0080, 0x00FF],
    "Latin_Extended-A" => [0x0100, 0x017F],
    "Latin_Extended-B" => [0x0180, 0x024F],
    "IPA_Extensions" => [0x0250, 0x02AF],
    "Spacing_Modifier_Letters" => [0x02B0, 0x02FF],
    "Combining_Diacritical_Marks" => [0x0300, 0x036F],
    "Greek_and_Coptic" => [0x0370, 0x03FF],
    "Cyrillic" => [0x0400, 0x04FF],
    "CJK_Unified_Ideographs" => [0x4E00, 0x9FFF],
    "CJK_Symbols_and_Punctuation" => [0x3000, 0x303F],
    "CJK_Radicals_Supplement" => [0x2E80, 0x2EFF],
    "CJK_Strokes" => [0x31C0, 0x31EF],
    "Enclosed_CJK_Letters_and_Months" => [0x3200, 0x32FF],
    "CJK_Unified_Ideographs_Extension_B" => [0x20000, 0x2A6DF],
    "CJK_Unified_Ideographs_Extension_C" => [0x2A700, 0x2B73F],
    "CJK_Unified_Ideographs_Extension_D" => [0x2B740, 0x2B81F],
    "CJK_Unified_Ideographs_Extension_E" => [0x2B820, 0x2CEAF],
    "CJK_Unified_Ideographs_Extension_F" => [0x2CEB0, 0x2EBEF],
    "CJK_Unified_Ideographs_Extension_G" => [0x30000, 0x3134F],
    "CJK_Unified_Ideographs_Extension_H" => [0x31350, 0x323AF],
    "CJK_Unified_Ideographs_Extension_J" => [0x31350, 0x323AF],
    "Tangut" => [0x17000, 0x187FF],
    "Tangut_Components" => [0x18800, 0x18AFF],
    "Tangut_Supplement" => [0x18D00, 0x18D7F],
    "Tolong_Siki" => [0x11DB0, 0x11DEF],
    "Sharada" => [0x11180, 0x111CD],
    "Sharada_Supplement" => [0x11B60, 0x11B7F],
    "Mathematical_Operators" => [0x2200, 0x22FF],
    "Supplemental_Mathematical_Operators" => [0x2A00, 0x2AFF],
    "Mathematical_Alphanumeric_Symbols" => [0x1D400, 0x1D7FF],
    "Miscellaneous_Mathematical_Symbols-A" => [0x27C0, 0x27EF],
    "Miscellaneous_Mathematical_Symbols-B" => [0x2980, 0x29FF],
    "Musical_Symbols" => [0x1D100, 0x1D1FF],
    "Miscellaneous_Symbols" => [0x2600, 0x26FF],
    "Miscellaneous_Technical" => [0x2300, 0x23FF],
    "Alchemical_Symbols" => [0x1F700, 0x1F77F],
    "Miscellaneous_Symbols_and_Pictographs" => [0x1F300, 0x1F5FF],
    "Supplemental_Symbols_and_Pictographs" => [0x1F900, 0x1F9FF],
    "Transport_and_Map_Symbols" => [0x1F680, 0x1F6FF],
    "Chess_Symbols" => [0x1FA00, 0x1FA0F],
    "Symbols_and_Pictographs_Extended-A" => [0x1FA70, 0x1FAFF],
    "Symbols_for_Legacy_Computing" => [0x1FB00, 0x1FBFF],
    "Imperial_Aramaic" => [0x10840, 0x1085F],
    "Phoenician" => [0x10900, 0x1091F],
    "Beria_Erfe" => [0x10940, 0x1095F],
    "Sidetic" => [0x10920, 0x1093F],
    "Egyptian_Hieroglyphs" => [0x13000, 0x1342F],
    "Egyptian_Hieroglyph_Format_Controls" => [0x13430, 0x1345F],
    "Egyptian_Hieroglyphs_Extended_A" => [0x13460, 0x143FF],
    "Egyptian_Hieroglyphs_Extended-B" => [0x16A40, 0x16A8F],
    "Supplemental_Arrows-C" => [0x1F800, 0x1F8FF],
    "Tai_Yo" => [0x16E40, 0x16E9F],
    "Emoticons" => [0x1F600, 0x1F64F],
    "Dingbats" => [0x2700, 0x27BF],
  }.freeze

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
        remap = YAML.safe_load(File.read(remap_path))
        if (remap["mappings"] || []).empty?
          warn "skip: donor #{label} codepoint_remap has no mappings yet (TODO)"
          next
        end
        # TODO: apply remap when scanning cmap (deferred until a donor
        # actually has a non-empty remap; see issue #3 tasks #6 + #13).
        warn "skip: donor #{label} codepoint_remap loaded but remap application not yet implemented"
        next
      end

      print "  loading #{label} (#{File.basename(path)})... "
      font_index = entry["font_index"] || 0
      begin
        font = Fontisan::FontLoader.load(path, font_index: font_index)
      rescue StandardError => e
        warn "skip: #{e.message}"
        next
      end
      coverage = scan_cmap(font)
      loaded[label] = {
        font: font,
        label: label,
        file: path,
        coverage: coverage,
        covers: entry["covers"] || [],
      }
      puts "#{coverage.size} codepoints"
    end

    loaded
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
      puts "  #{output_path} (#{File.size(output_path)} bytes)"
    end
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
