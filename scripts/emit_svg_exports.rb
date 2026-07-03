#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract per-codepoint SVG files from an SFNT font (TTF or OTF).
#
# Pipeline:
#   1. Convert the input font to SVG-font format via fontisan's SvgGenerator.
#      (SVG fonts are deprecated as a delivery format, but they encode every
#       glyph outline as a `<glyph d="...">` element we can extract.)
#   2. Parse the SVG-font XML with nokogiri.
#   3. For each `<glyph>` element with a `unicode` attribute, emit a
#      standalone SVG file at out-dir/U+XXXX.svg.
#   4. Emit index.json mapping filename → {cp, name, donor?}.
#
# Usage:
#   ruby scripts/emit_svg_exports.rb [INPUT.ttf|INPUT.otf] [OUT_DIR]
#
# Defaults:
#   INPUT = Essenfont-Regular.otc (uses face 0) or Essenfont-Regular.ttf
#   OUT_DIR = svg-exports/

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "fileutils"
require "nokogiri"

module EmitSvgExports
  def self.emit(input_path:, out_dir:, donor_map: {})
    input_path ||= detect_input
    raise "input not found: #{input_path}" unless File.exist?(input_path)

    FileUtils.rm_rf(out_dir)
    FileUtils.mkdir_p(out_dir)

    puts "→ loading #{input_path}"
    font = Fontisan::FontLoader.load(input_path)
    head = font.table("head")
    units_per_em = head&.units_per_em || 1000

    puts "→ generating SVG-font XML via fontisan"
    svg_xml = Fontisan::Converters::SvgGenerator.new.convert(font)[:svg_xml]

    puts "→ indexing cmap (gid → codepoints)"
    cmap = font.table("cmap")&.unicode_mappings || {}
    gid_to_cps = {}
    cmap.each { |cp, gid| (gid_to_cps[gid] ||= []) << cp }

    puts "→ parsing and emitting per-codepoint SVGs"
    doc = Nokogiri::XML(svg_xml)
    glyphs = doc.css("glyph")

    puts "  #{glyphs.size} glyph elements in SVG-font XML"
    puts "  #{gid_to_cps.size} gids mapped via cmap"

    index = {}
    counts = { emitted: 0, skipped_no_path: 0, skipped_no_unicode: 0 }

    glyphs.each_with_index do |glyph, gid|
      path_d = glyph["d"]
      cps = gid_to_cps[gid] || []

      if cps.empty?
        counts[:skipped_no_unicode] += 1
        next
      end

      if path_d.nil? || path_d.strip.empty?
        counts[:skipped_no_path] += 1
        next
      end

      cps.each do |cp|
        hex = cp.to_s(16).upcase
        filename = "U+#{hex}.svg"
        out_path = File.join(out_dir, filename)

        File.write(out_path, render_svg(cp, "", path_d, units_per_em, donor_map[cp]))

        index[filename] = {
          cp: "0x#{hex}",
          name: glyph["glyph-name"] || "",
          donor: donor_map[cp] && donor_map[cp][:label]
        }.compact
        counts[:emitted] += 1
      end
    end

    File.write(File.join(out_dir, "index.json"),
               JSON.pretty_generate(
                 essenfont_version: Essenfont::Otc::Version::STRING,
                 generated_at: Time.now.utc.iso8601,
                 source: input_path,
                 total_svgs: counts[:emitted],
                 files: index
               ))

    puts "✓ wrote #{counts[:emitted]} SVGs to #{out_dir}/"
    puts "  (#{counts[:skipped_no_path]} had no outline, #{counts[:skipped_no_unicode]} had no unicode)"
    puts "  index.json written"
  end

  def self.detect_input
    %w[Essenfont-Regular.otc Essenfont-Regular.ttc Essenfont-BMP.ttf].each do |p|
      return p if File.exist?(p)
    end
    raise "no input font found — pass INPUT.ttf as the first argument"
  end

  # The SVG-font `unicode="..."` attribute can be a single character,
  # an XML numeric entity (&#x1F600;), or a multi-character sequence.
  # We extract codepoints.
  def self.parse_unicode_attribute(text)
    return [] unless text

    # Decode XML entities first
    decoded = text.gsub(/&#x([0-9A-Fa-f]+);/) { [$1.to_i(16)].pack("U") }
                  .gsub(/&#(\d+);/) { [$1.to_i].pack("U") }

    decoded.codepoints.to_a
  rescue StandardError
    []
  end

  def self.render_svg(cp, name, path_d, units_per_em, donor_info)
    hex = cp.to_s(16).upcase
    donor_meta = ""
    if donor_info
      donor_meta = <<-META
      <donor>#{escape_xml(donor_info[:label].to_s)}</donor>
      <donor-version>#{escape_xml(donor_info[:version].to_s)}</donor-version>
      <license>#{escape_xml(donor_info[:license].to_s)}</license>
    META
    end

    <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{units_per_em} #{units_per_em}" width="#{units_per_em}" height="#{units_per_em}">
        <metadata>
          <codepoint>U+#{hex}</codepoint>
          <name>#{escape_xml(name)}</name>
          #{donor_meta}<essenfont-version>#{Essenfont::Otc::Version::STRING}</essenfont-version>
          <generated-at>#{Time.now.utc.iso8601}</generated-at>
        </metadata>
        <g transform="translate(0, #{units_per_em}) scale(1, -1)">
          <path d="#{path_d}"/>
        </g>
      </svg>
    SVG
  end

  def self.escape_xml(str)
    str.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end
end

require "time"
require "essenfont"
require "fontisan"

input = ARGV[0]
out_dir = ARGV[1] || "svg-exports"
donor_map_path = ENV.fetch("DONOR_MAP", "cp_map.json")
donor_map = {}
if File.exist?(donor_map_path)
  data = JSON.parse(File.read(donor_map_path))
  donor_map = data.transform_values { |v| { label: v["label"] || v[:label] } }
  donor_map = donor_map.transform_keys { |k| k.to_i(16) rescue k.to_i }
  puts "→ loaded #{donor_map.size} cps from #{donor_map_path}"
end

EmitSvgExports.emit(input_path: input, out_dir: out_dir, donor_map: donor_map)
