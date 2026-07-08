#!/usr/bin/env ruby
# frozen_string_literal: true

# Build Essenfont from donor fonts.
#
# Usage:
#   ruby scripts/build.rb                    # TTC, glyf outlines (default)
#   ruby scripts/build.rb --format=otc       # same as default
#   ruby scripts/build.rb --format=otc-cff2  # OTC, CFF2 outlines (~35% smaller)
#   ruby scripts/build.rb --format=ttf-per-plane
#   ruby scripts/build.rb --format=ttf       # legacy single BMP-only TTF
#   ruby scripts/build.rb --format=otf       # legacy single BMP-only OTF
#
# This is a thin entry point. All the work happens in lib/essenfont/:
#   - Manifest      reads sources/manifest.yml
#   - DonorLoader   loads + verifies each donor
#   - CpMap         builds + filters the per-codepoint donor map
#   - UcodeRef      Unicode metadata (no hardcoded paths)
#   - Otc::Build    the orchestrator that calls fontisan's Stitcher

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "optparse"
require "essenfont"

module EssenfontBuild
  OUTPUT_DIR = File.expand_path("..", __dir__)

  module_function

  def run(format: :otc)
    puts "=== Essenfont build (format: #{format}) ==="

    manifest = Essenfont::Manifest.load
    puts "  manifest: #{manifest.size} entries (#{manifest.active.size} active)"

    donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
    raise_build_error "no donor fonts loaded — check sources/manifest.yml + references/input-fonts/" if donors.empty?

    validate_coverage_gates(manifest:, donors:)

    cp_map = build_cp_map(donors)
    raise_build_error "no codepoints covered by any donor" if cp_map.size.zero?

    dump_cp_map_if_requested(cp_map)

    case format.to_sym
    when :otc
      build_otc(cp_map:, donors:, subfont_format: :ttf)
    when :otc_cff2
      build_otc(cp_map:, donors:, subfont_format: :otf2)
    when :'ttf-per-plane'
      build_per_plane_ttfs(cp_map:, donors:)
    when :ttf
      warn "INFO: --format=ttf emits a single BMP-only font. " \
           "Use the default (--format=otc) for full Unicode coverage."
      build_legacy_single(cp_map:, donors:, format: :ttf)
    when :otf
      warn "INFO: --format=otf emits a single BMP-only font. " \
           "Use the default (--format=otc) for full Unicode coverage."
      build_legacy_single(cp_map:, donors:, format: :otf)
    else
      raise_build_error "unknown format #{format.inspect} " \
                        "(use :otc, :otc-cff2, :ttf-per-plane, :ttf, or :otf)"
    end
  end

  # ── CpMap assembly: scan → filter → backfill ──
  def build_cp_map(donors)
    raw = Essenfont::CpMap.from_donors(donors)
    puts "  total codepoints across donors: #{raw.size}"

    filtered = raw.filter_reserved
    puts "  after filtering PUA/Surrogate/Specials: #{filtered.size}"

    first_label = donors.values.first[:label]
    backfilled = filtered.backfill_cc_cf(first_label)
    puts "  after Cc/Cf backfill: #{backfilled.size}"
    backfilled
  end

  # ── Coverage gate ──
  # Validates that declared covers: blocks actually have cmap coverage.
  # Delegates to Essenfont::CoverageGate — single source of truth
  # shared with scripts/release.rb.
  def validate_coverage_gates(manifest:, donors:)
    Essenfont::CoverageGate.new(manifest:, donors:).validate!
  end

  # ── OTC (canonical) ──
  def build_otc(cp_map:, donors:, subfont_format:)
    puts "=== Partitioning #{cp_map.size} codepoints by Unicode plane " \
         "(subfont outlines: #{subfont_format}) ==="

    ext = subfont_format == :ttf ? ".ttc" : ".otc"
    suffix = subfont_format == :otf2 ? "-CFF2" : (subfont_format == :otf ? "-CFF1" : "")
    output_path = File.join(OUTPUT_DIR, "Essenfont#{suffix}-Regular#{ext}")

    result = Essenfont::Otc::Build.new(
      cp_map: cp_map,
      donors: donors,
      subfont_format: subfont_format
    ).call(output_path:)

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

  # ── Per-plane TTFs (legacy / web embed source) ──
  def build_per_plane_ttfs(cp_map:, donors:)
    puts "=== Partitioning #{cp_map.size} codepoints by Unicode plane ==="

    partitioner = Fontisan::Stitcher::PartitionStrategy::ByPlane.new
    blueprint = partitioner.call(cp_map.donor_labels)
    subfont_names = blueprint.names
    puts "  #{subfont_names.size} subfonts: #{subfont_names.join(', ')}"

    stitcher = Fontisan::Stitcher.new
    donors.each_value do |d|
      stitcher.add_source(d[:label], d[:font], remap: d[:remap])
    end
    blueprint.apply_to(stitcher)

    catalog = Essenfont::UcodeRef.catalog
    subfont_names.each do |name|
      plane_num = name.to_s.sub("plane_", "").to_i
      plane = catalog.find_plane(plane_num)
      face_name = plane&.short_name&.to_s || name.to_s
      out = File.join(OUTPUT_DIR, "Essenfont-#{face_name}.ttf")
      puts "=== Writing #{out} ==="
      stitcher.write_to(out, format: :ttf, subfont: name)
      puts "  #{out} (#{File.size(out)} bytes)"
    end
  end

  # ── Legacy single-font (TTF or OTF, BMP only) ──
  def build_legacy_single(cp_map:, donors:, format:)
    bmp_map = cp_map.map.select { |cp, _| cp <= 0xFFFF }
    puts "=== Stitching #{bmp_map.size} BMP codepoints (legacy #{format}) ==="

    stitcher = Fontisan::Stitcher.new
    donors.each_value do |d|
      stitcher.add_source(d[:label], d[:font], remap: d[:remap])
    end

    first_label = donors.values.first[:label]
    stitcher.include_notdef(from: first_label, into: :legacy)

    bmp_map.each_slice(1000) do |slice|
      slice.each do |cp, info|
        stitcher.include_codepoints([cp], from: info[:label], into: :legacy)
      end
    end

    ext = format == :otf ? "otf" : "ttf"
    output_path = File.join(OUTPUT_DIR, "Essenfont-Regular.#{ext}")
    puts "=== Writing #{output_path} ==="
    stitcher.write_to(output_path, format: format, subfont: :legacy)
    puts "  #{output_path} (#{File.size(output_path)} bytes)"
  end

  # ── Post-write validation via Fontisan::Collection::Reader ──
  def validate_collection!(path, expected_faces:, expected_cmap_union_size:)
    reader = Fontisan::Collection::Reader.open(path)
    unless reader.face_count == expected_faces
      raise_collection_validation "#{path} has #{reader.face_count} faces, expected #{expected_faces}"
    end

    reader.stats.each do |s|
      next if s.glyph_count <= 65_535

      raise_collection_validation "face #{s.index} has #{s.glyph_count} glyphs (cap 65,535)"
    end

    union_size = reader.cmap_union.size
    return unless union_size < expected_cmap_union_size * 0.99

    dropped = expected_cmap_union_size - union_size
    warn "  WARNING: cmap union dropped #{dropped} entries " \
         "(#{union_size} / #{expected_cmap_union_size})"
  end

  # ── cp_map.json dump for downstream attribution ──
  def dump_cp_map_if_requested(cp_map)
    return unless ENV["ESSENFONT_DUMP_CP_MAP"]

    path = File.join(OUTPUT_DIR, "cp_map.json")
    File.write(path, JSON.pretty_generate(cp_map.donor_labels))
    puts "wrote #{path} (#{cp_map.size} cps)"
  end

  # ── Errors ──
  def raise_build_error(message)
    raise Essenfont::Otc::Errors::BuildError, message
  end

  def raise_collection_validation(message)
    raise Essenfont::Otc::Errors::CollectionValidation, message
  end
end

require "json"

if __FILE__ == $PROGRAM_NAME
  options = { format: :otc }
  OptionParser.new do |opts|
    opts.banner = "Usage: build.rb [options]"
    opts.on("--format=FORMAT", "otc (default), otc-cff2, ttf-per-plane, ttf, or otf") do |v|
      options[:format] = v.tr("-", "_").to_sym
    end
  end.parse!

  begin
    EssenfontBuild.run(format: options[:format])
  rescue Essenfont::Otc::Errors::Base => e
    warn "ERROR: #{e.class.name.split('::').last}: #{e.message}"
    exit 1
  end
end
