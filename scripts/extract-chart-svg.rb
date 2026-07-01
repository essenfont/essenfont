#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual code-chart SVG extractor for blocks where ucode's extractor
# returns 0 (Garay, Ol Onal, etc.). Uses pdf2svg's output and the
# known grid layout to split per-codepoint SVGs.
#
# Usage: ruby extract-chart-svg.rb <input.svg> <block_first_cp> <block_last_cp> <output_dir>

require "rexml/document"
require "fileutils"

input_svg = ARGV[0]
first_cp = ARGV[1].to_i(16)
last_cp = ARGV[2].to_i(16)
output_dir = ARGV[3]

FileUtils.mkdir_p(output_dir)

doc = REXML::Document.new(File.read(input_svg))

# Collect all glyph defs: {glyph_id => path_data}
glyph_defs = {}
REXML::XPath.each(doc, "//defs//g") do |g|
  id = g.attributes["id"]
  next unless id && id =~ /^glyph-/
  path = REXML::XPath.first(g, ".//path")
  glyph_defs[id] = path.attributes["d"] if path
end

puts "Found #{glyph_defs.size} glyph definitions"

# Collect all <use> elements with their positions
uses = []
REXML::XPath.each(doc, "//use") do |u|
  href = u.attributes["xlink:href"] || u.attributes["href"]
  next unless href
  id = href.sub(/^#/, "")
  next unless glyph_defs.key?(id)

  x = (u.attributes["x"] || "0").to_f
  y = (u.attributes["y"] || "0").to_f
  uses << { glyph_id: id, x: x, y: y, path: glyph_defs[id] }
end

puts "Found #{uses.size} <use> references"

# Group uses by Y-coordinate (rows). The chart grid has cells at
# regular Y intervals. Cluster uses into rows.
uses.sort_by! { |u| [u[:y], u[:x]] }
rows = []
current_row = []
current_y = nil
uses.each do |u|
  if current_y.nil? || (u[:y] - current_y).abs < 3
    current_row << u
    current_y ||= u[:y]
  else
    rows << current_row if current_row.any?
    current_row = [u]
    current_y = u[:y]
  end
end
rows << current_row if current_row.any?

puts "Clustered into #{rows.size} Y-rows"

# Within each row, sort by X. Filter to only rows that have exactly
# 1 glyph use (the actual script glyphs, not the Latin text which
# has multiple use elements per line for the character names).
# The Garay chart grid cells have exactly 1 glyph each.
script_rows = rows.select { |r| r.size == 1 }
puts "Single-glyph rows (likely script glyphs): #{script_rows.size}"

# Also check multi-glyph rows that might contain script glyphs
# (some charts put the glyph + a small number in the same row)
# For now, use single-glyph rows as they're the clearest signal.
candidate_glyphs = script_rows.map { |r| r.first }

puts "Candidate glyphs: #{candidate_glyphs.size}"

# Map to codepoints. The chart lists codepoints in order.
# If the count matches the assigned range, map 1:1.
total_assigned = last_cp - first_cp + 1
puts "Assigned codepoints in range: #{total_assigned}"

if candidate_glyphs.size <= total_assigned
  candidate_glyphs.each_with_index do |g, i|
    cp = first_cp + i
    break if cp > last_cp

    svg = <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
        <g transform="translate(500, 800) scale(100, -100)">
          <path d="#{g[:path]}" fill="black"/>
        </g>
      </svg>
    SVG

    cp_hex = "U+#{cp.to_s(16).upcase}"
    File.write(File.join(output_dir, "#{cp_hex}.svg"), svg)

    sidecar = {
      codepoint: cp_hex,
      source: "pdf2svg manual extraction",
      glyph_id: g[:glyph_id],
      original_position: { x: g[:x], y: g[:y] },
    }
    File.write(File.join(output_dir, "#{cp_hex}.json"), JSON.pretty_generate(sidecar))
  end
  puts "Wrote #{candidate_glyphs.size} SVG + JSON pairs to #{output_dir}"
else
  puts "WARNING: more candidate glyphs (#{candidate_glyphs.size}) than codepoints (#{total_assigned})"
  puts "Filtering may be needed. Writing first #{total_assigned}..."
  candidate_glyphs.first(total_assigned).each_with_index do |g, i|
    cp = first_cp + i
    cp_hex = "U+#{cp.to_s(16).upcase}"
    svg = <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
        <g transform="translate(500, 800) scale(100, -100)">
          <path d="#{g[:path]}" fill="black"/>
        </g>
      </svg>
    SVG
    File.write(File.join(output_dir, "#{cp_hex}.svg"), svg)
  end
  puts "Wrote #{total_assigned} SVGs (may need verification)"
end
