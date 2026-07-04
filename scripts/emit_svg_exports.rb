#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract per-codepoint SVG files from an SFNT font (TTF or OTF).
#
# fontisan 0.4.9+ SvgGenerator emits per-glyph `unicode=` + `glyph-name=`
# attributes (issue fontisan#80), so we no longer need to rebuild a
# gid → codepoints reverse map. Just parse the XML and emit one file
# per codepoint in each glyph's `unicode=` attribute.
#
# Donor attribution is optional; pass cp_map.json via $DONOR_MAP.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "fileutils"
require "nokogiri"
require "essenfont"
require "fontisan"

module EmitSvgExports
  module_function

  def emit(input_path:, out_dir:, donor_map: {})
    input_path ||= detect_input
    raise ArgumentError, "input not found: #{input_path}" unless File.exist?(input_path)

    FileUtils.rm_rf(out_dir)
    FileUtils.mkdir_p(out_dir)

    puts "→ loading #{input_path}"
    font = Fontisan::FontLoader.load(input_path)
    units_per_em = font.table("head")&.units_per_em || 1000

    puts "→ generating SVG-font XML (fontisan emits unicode= + glyph-name=)"
    svg_xml = Fontisan::Converters::SvgGenerator.new.convert(font)[:svg_xml]

    puts "→ parsing and emitting per-codepoint SVGs"
    doc = Nokogiri::XML(svg_xml)
    glyphs = doc.css("glyph").select { |g| g["unicode"] }
    puts "  #{glyphs.size} glyphs with unicode mappings"

    index = {}
    counts = Hash.new(0)

    glyphs.each do |glyph|
      path_d = glyph["d"]
      if path_d.nil? || path_d.strip.empty?
        counts[:skipped_no_path] += 1
        next
      end

      cps = parse_unicode_attribute(glyph["unicode"])
      if cps.empty?
        counts[:skipped_no_unicode] += 1
        next
      end

      cps.each do |cp|
        hex = cp.to_s(16).upcase
        filename = "U+#{hex}.svg"
        File.write(File.join(out_dir, filename),
                   render_svg(cp, glyph["glyph-name"] || "", path_d, units_per_em, donor_map[cp]))
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
  end

  def detect_input
    %w[Essenfont-Regular.otc Essenfont-Regular.ttc Essenfont-BMP.ttf].each do |p|
      return p if File.exist?(p)
    end
    raise ArgumentError, "no input font found — pass INPUT.ttf as the first argument"
  end

  # The SVG-font `unicode="..."` attribute can be a single character,
  # an XML numeric entity (&#x1F600;), or a multi-character sequence.
  def parse_unicode_attribute(text)
    return [] unless text

    decoded = text.gsub(/&#x([0-9A-Fa-f]+);/) { [$1.to_i(16)].pack("U") }
                  .gsub(/&#(\d+);/) { [$1.to_i].pack("U") }

    decoded.codepoints.to_a
  rescue StandardError
    []
  end

  def render_svg(cp, name, path_d, units_per_em, donor_info)
    hex = cp.to_s(16).upcase
    name_meta = name.empty? ? "" : "<name>#{escape_xml(name)}</name>\n          "
    donor_meta = donor_info ? <<-META : ""
      <donor>#{escape_xml(donor_info[:label].to_s)}</donor>
      <license>#{escape_xml(donor_info[:license].to_s)}</license>
    META

    <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{units_per_em} #{units_per_em}" width="#{units_per_em}" height="#{units_per_em}">
        <metadata>
          <codepoint>U+#{hex}</codepoint>
          #{name_meta}#{donor_meta}<essenfont-version>#{Essenfont::Otc::Version::STRING}</essenfont-version>
          <generated-at>#{Time.now.utc.iso8601}</generated-at>
        </metadata>
        <g transform="translate(0, #{units_per_em}) scale(1, -1)">
          <path d="#{path_d}"/>
        </g>
      </svg>
    SVG
  end

  def escape_xml(str)
    str.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end
end

require "time"

input = ARGV[0]
out_dir = ARGV[1] || "svg-exports"

donor_map = {}
cp_map_path = ENV.fetch("DONOR_MAP", "cp_map.json")
if File.exist?(cp_map_path)
  data = JSON.parse(File.read(cp_map_path))
  donor_map = data.transform_values { |v| { label: (v["label"] || v[:label]).to_sym } }
                  .transform_keys { |k| k.to_i(16) rescue k.to_i }
  puts "→ loaded #{donor_map.size} cps from #{cp_map_path}"
end

EmitSvgExports.emit(input_path: input, out_dir: out_dir, donor_map: donor_map)
