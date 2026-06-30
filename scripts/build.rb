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
require "fontisan"

module EssenfontBuild
  MANIFEST_PATH = File.expand_path("../sources/manifest.yml", __dir__)
  DONOR_DIR = File.expand_path("../references/input-fonts", __dir__)
  OUTPUT_DIR = File.expand_path("..", __dir__)
  UCODE_MANIFEST = ENV.fetch("UCODE_MANIFEST", nil)

  # Parse the donor manifest and load each available donor.
  # @return [Hash<Symbol, {font:, label:, file:, coverage:}>]
  def self.load_donors
    manifest = YAML.safe_load(File.read(MANIFEST_PATH))
    donors = manifest["donors"] || []
    loaded = {}

    donors.each do |entry|
      label = entry["label"].to_sym
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
        coverage: coverage
      }
      puts "#{coverage.size} codepoints"
    end

    loaded
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
