#!/usr/bin/env ruby
# frozen_string_literal: true

# Build Essenfont from donor fonts.
#
# Usage:
#   ruby scripts/build.rb                          # builds Essenfont-Regular.otc (default)
#   ruby scripts/build.rb --format=otc             # explicit OTC (multi-subfont)
#   ruby scripts/build.rb --format=ttf-per-plane   # one TTF per Unicode plane
#   ruby scripts/build.rb --format=ttf             # legacy: single BMP-only TTF
#   ruby scripts/build.rb --format=otf             # legacy: single BMP-only OTF
#
# The default OTC output partitions codepoints across Unicode planes so
# each subfont stays under the TrueType 65,535-glyph cap. See
# TODO.otc-essenfont/ for the full spec.
#
# The build:
# 1. Reads sources/manifest.yml → donor font registry
# 2. Loads each donor via Fontisan::FontLoader.load
# 3. Scans each donor's cmap → per-codepoint coverage
# 4. For each codepoint: extracts glyph from the first covering donor
# 5. Partitions codepoints by Unicode plane (BMP, SMP, SIP, TIP, SSP)
# 6. For OTC: emits one subfont per non-empty plane via Fontisan::Collection::Builder
#    For TTF/OTF: stitches all BMP codepoints into one font (legacy, cap-bound)

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "optparse"
require "yaml"
require "json"
require "fileutils"
require "digest"
require "fontisan"
require "essenfont"

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
        generated_dir = File.expand_path("../references/input-fonts/.generated/svg-donors", __dir__)
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
  # (in manifest order) that covers it. Codepoints in PUA, Surrogate,
  # or Specials ranges are excluded — they're not Unicode-assigned
  # characters and would only bloat the output font with donor
  # internal/PUA assignments (e.g., FSung-X's Plane 16 PUA bleed).
  # @param donors [Hash] loaded donors
  # @return [Hash<Integer, {label:, gid:}>]
  def self.build_codepoint_map(donors)
    all_cps = Set.new
    donors.each_value { |d| all_cps.merge(d[:coverage].keys) }

    # Filter: drop codepoints in PUA / Surrogate / Specials ranges.
    # These are Unicode "non-character" zones — never assigned, never
    # renderable as real characters. Donor cps in these ranges are
    # either the donor's internal encoding (PUA) or encoding artifacts.
    reserved_ranges = [
      (0xE000..0xF8FF),     # Private Use Area
      (0xF0000..0xFFFFD),   # Supplementary Private Use Area-A
      (0x100000..0x10FFFD), # Supplementary Private Use Area-B
      (0xD800..0xDFFF),     # Surrogates
      (0xFFF0..0xFFFF),     # Specials (U+FFF0..U+FFFF — half of Specials block)
      (0xFFFE..0xFFFF),     # (the other half; non-characters)
      (0x1FFFE..0x1FFFF), (0x2FFFE..0x2FFFF), (0x3FFFE..0x3FFFF),
      (0x4FFFE..0x4FFFF), (0x5FFFE..0x5FFFF), (0x6FFFE..0x6FFFF),
      (0x7FFFE..0x7FFFF), (0x8FFFE..0x8FFFF), (0x9FFFE..0x9FFFF),
      (0xAFFFE..0xAFFFF), (0xBFFFE..0xBFFFF), (0xCFFFE..0xCFFFF),
      (0xDFFFE..0xDFFFF), (0xEFFFE..0xEFFFF), (0xFFFFE..0xFFFFF),
      (0x10FFFE..0x10FFFF),
    ]
    original_size = all_cps.size
    all_cps = all_cps.reject { |cp| reserved_ranges.any? { |r| r.cover?(cp) } }
    puts "  total codepoints across all donors: #{original_size}"
    puts "  after filtering PUA/Surrogate/Specials: #{all_cps.size} (dropped #{original_size - all_cps.size})"

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

    # Backfill Cc (Control) + Cf (Format) codepoints that no donor
    # covers. These are assigned Unicode characters (per UCD
    # General_Category) but rarely have glyphs in donor fonts. Map them
    # to .notdef (gid 0) from the first donor so every assigned
    # codepoint is reachable in the output font. This brings coverage
    # to 100% for Cc/Cf and fixes the "missing 31 Basic Latin
    # codepoints" UX issue (those 31 are the C0 controls).
    backfilled = 0
    (0x0000..0x001F).each do |cp|  # C0
      cp_map[cp] ||= { label: donors.values.first[:label], gid: 0 }
      backfilled += 1 unless cp_map[cp][:gid] != 0
    end
    (0x007F..0x009F).each do |cp|  # DEL + C1
      cp_map[cp] ||= { label: donors.values.first[:label], gid: 0 }
      backfilled += 1 unless cp_map[cp][:gid] != 0
    end
    (0x200B..0x200F).each do |cp|  # ZWSP/ZWNJ/ZWJ marks
      cp_map[cp] ||= { label: donors.values.first[:label], gid: 0 }
    end
    (0x202A..0x202E).each do |cp|  # bidi LRM/RLM marks
      cp_map[cp] ||= { label: donors.values.first[:label], gid: 0 }
    end
    (0x2060..0x2064).each do |cp|  # Word joiner
      cp_map[cp] ||= { label: donors.values.first[:label], gid: 0 }
    end
    cp_map[0xFEFF] ||= { label: donors.values.first[:label], gid: 0 }

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
  # @param format [Symbol] :otc (default, multi-subfont collection),
  #   :ttf (legacy single BMP-only TTF), or :otf (legacy single BMP-only OTF)
  def self.run(format: :otc)
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

    dump_cp_map_if_requested(cp_map)

    case format.to_sym
    when :otc
      build_otc(cp_map:, donors:, subfont_format: :ttf)
    when :otc_cff2
      build_otc(cp_map:, donors:, subfont_format: :otf2)
    when :"ttf-per-plane"
      build_per_plane_ttfs(cp_map:, donors:)
    when :ttf
      warn "INFO: --format=ttf emits a single BMP-only font. " \
           "Use the default (--format=otc) for full Unicode coverage."
      build_legacy_single(cp_map:, donors:, format: :ttf)
    when :otf
      warn "INFO: --format=otf emits a single BMP-only font. " \
           "Use the default (--format=otc) for full Unicode coverage."
      build_legacy_single(cp_map:, donors:, format: :otf)
    when :all
      build_otc(cp_map:, donors:, subfont_format: :ttf)
    else
      warn "ERROR: unknown format #{format.inspect} " \
           "(use :otc, :otc-cff2, :ttf-per-plane, :ttf, or :otf)"
      exit 1
    end
  end

  # Build the OTC: partitions codepoints across Unicode planes and emits
  # one subfont per plane via Essenfont::Otc::Build (which delegates to
  # Fontisan::Stitcher::PartitionStrategy::ByPlane + Stitcher#write_collection).
  # @param cp_map [Hash<Integer, {label:, gid:}>]
  # @param donors [Hash<Symbol, {font:, label:, ...}>]
  # @param subfont_format [Symbol] :ttf (glyf outlines) or :otf2 (CFF2 outlines)
  def self.build_otc(cp_map:, donors:, subfont_format: :ttf)
    puts "=== Partitioning #{cp_map.size} codepoints by Unicode plane " \
         "(subfont outlines: #{subfont_format}) ==="

    ext = subfont_format == :ttf ? ".ttc" : ".otc"
    suffix = subfont_format == :otf2 ? "-CFF2" : (subfont_format == :otf ? "-CFF1" : "")
    output_path = File.join(OUTPUT_DIR, "Essenfont#{suffix}-Regular#{ext}")
    build = Essenfont::Otc::Build.new(
      cp_map: cp_map,
      donors: donors,
      subfont_format: subfont_format
    )
    result = build.call(output_path:)

    puts "=== Wrote #{output_path} (#{result.bytes} bytes) ==="
    puts "  subfonts (#{result.subfont_count}):"
    result.subfonts.each do |sf|
      puts "    #{sf[:name]}: #{sf[:glyph_count]} glyphs, #{sf[:codepoint_count]} codepoints"
    end

    validate_collection!(output_path,
                         expected_faces: result.subfont_count,
                         expected_cmap_union_size: cp_map.size)
    puts "  validated: #{result.subfont_count} faces, all under 65,535-glyph cap"
  end

  # Build per-plane TTFs: same partitioning as build_otc, but each
  # subfont is written as a separate TTF file. Used by the website for
  # clients that can't consume OTC (e.g., WOFF2 web embedding).
  def self.build_per_plane_ttfs(cp_map:, donors:)
    puts "=== Partitioning #{cp_map.size} codepoints by Unicode plane ==="

    partitioner = Fontisan::Stitcher::PartitionStrategy::ByPlane.new
    donor_labels = cp_map.transform_values { |info| info[:label] }
    blueprint = partitioner.call(donor_labels)
    subfont_names = blueprint.names
    puts "  #{subfont_names.size} subfonts: #{subfont_names.join(', ')}"

    stitcher = Fontisan::Stitcher.new
    donors.each_value { |d| stitcher.add_source(d[:label], d[:font]) }
    blueprint.apply_to(stitcher)

    catalog = Ucode::Unicode.for_version
    subfont_names.each do |name|
      plane = catalog.find_plane(name.to_s.sub("plane_", "").to_i)
      face_name = plane&.short_name&.to_s || name.to_s
      out = File.join(OUTPUT_DIR, "Essenfont-#{face_name}.ttf")
      puts "=== Writing #{out} ==="
      stitcher.write_to(out, format: :ttf, subfont: name)
      validate_and_repair_cmap(out)
      puts "  #{out} (#{File.size(out)} bytes)"
    end
  end

  # Legacy single-font path (TTF or OTF). Uses only BMP codepoints to
  # stay under the 65,535-glyph cap. Kept for backward compatibility
  # and per-plane debugging.
  def self.build_legacy_single(cp_map:, donors:, format:)
    bmp_map = cp_map.select { |cp, _| cp <= 0xFFFF }
    puts "=== Stitching #{bmp_map.size} BMP codepoints (legacy #{format}) ==="

    stitcher = Fontisan::Stitcher.new
    donors.each_value { |d| stitcher.add_source(d[:label], d[:font]) }

    first_label = donors.values.first[:label]
    stitcher.include_notdef(from: first_label, into: :legacy)

    bmp_map.each_slice(1000) do |slice|
      slice.each do |cp, info|
        stitcher.include_codepoints([cp], from: info[:label], into: :legacy)
      end
      print "\r  #{bmp_map.keys.index(slice.last[0]) + 1}/#{bmp_map.size} stitched"
    end
    puts

    ext = format == :otf ? "otf" : "ttf"
    output_path = File.join(OUTPUT_DIR, "Essenfont-Regular.#{ext}")
    puts "=== Writing #{output_path} ==="
    stitcher.write_to(output_path, format: format, subfont: :legacy)
    validate_and_repair_cmap(output_path)
    puts "  #{output_path} (#{File.size(output_path)} bytes)"
  end

  # Post-write sanity check for OTC output:
  #   1. TTC header reports the expected face count.
  #   2. Every face's maxp.num_glyphs ≤ 65,535.
  #   3. Union of face cmap entries matches the input cp_map size.
  # Dump cp_map as JSON for downstream tooling (license attribution,
  # provenance explorer). Triggered by ESSENFONT_DUMP_CP_MAP=1.
  def self.dump_cp_map_if_requested(cp_map)
    return unless ENV["ESSENFONT_DUMP_CP_MAP"]

    path = File.join(OUTPUT_DIR, "cp_map.json")
    simplified = cp_map.transform_values { |v| { label: v[:label] } }
    File.write(path, JSON.pretty_generate(simplified))
    puts "wrote #{path} (#{cp_map.size} cps)"
  end

  def self.validate_collection!(path, expected_faces:, expected_cmap_union_size:)
    reader = Fontisan::Collection::Reader.open(path)
    if reader.face_count != expected_faces
      raise "#{path} has #{reader.face_count} faces, expected #{expected_faces}"
    end

    reader.stats.each do |s|
      next if s.glyph_count <= 65_535
      raise "face #{s.index} has #{s.glyph_count} glyphs (cap 65,535)"
    end

    union_size = reader.cmap_union.size
    if union_size < expected_cmap_union_size * 0.99
      dropped = expected_cmap_union_size - union_size
      warn "  WARNING: cmap union dropped #{dropped} entries " \
           "(#{union_size} / #{expected_cmap_union_size})"
    end
  rescue StandardError => e
    warn "  collection validation failed: #{e.message}"
    exit 1
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
  options = { format: :otc }
  OptionParser.new do |opts|
    opts.banner = "Usage: build.rb [options]"
    opts.on("--format=FORMAT",
            "otc (default), otc-cff2, ttf-per-plane, ttf, or otf") do |v|
      options[:format] = v.to_sym
    end
  end.parse!

  EssenfontBuild.run(format: options[:format])
end
