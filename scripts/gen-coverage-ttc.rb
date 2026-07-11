#!/usr/bin/env ruby
# frozen_string_literal: true

# TTC-aware coverage report. Unions the cmap of every face in the
# Essenfont TTC and emits per-block coverage to the website's
# public/coverage.json.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "time"
require "fontisan"
require "essenfont"

TTC_FILE = ARGV[0] || "Essenfont-Regular.ttc"

unless File.exist?(TTC_FILE)
  warn "TTC not found: #{TTC_FILE}"
  exit 1
end

catalog = Essenfont::UcodeRef.catalog

# Union every face's cmap.
union_cmap = Set.new
File.open(TTC_FILE, "rb") do |io|
  ttc = Fontisan::TrueTypeCollection.read(io)
  ttc.num_fonts.times do |i|
    io.rewind
    face = ttc.font(i, io)
    next unless face

    cmap = face.table("cmap")&.unicode_mappings || {}
    cmap.each_key { |cp| union_cmap << cp }
  end
  puts "Union cmap across #{ttc.num_fonts} faces: #{union_cmap.size} codepoints"
end

report = Essenfont::CoverageReport.new(union_cmap, catalog: catalog)

output = {
  generated_at: Time.now.utc.iso8601,
  unicode_version: catalog.version,
  source: TTC_FILE,
  overall: report.summary.merge(cmap_union: union_cmap.size),
  totals: report.summary,
  blocks: report.per_block
}

json_path = File.join(File.dirname(__FILE__), "..", "..", "essenfont.github.io", "public", "coverage.json")
File.write(json_path, JSON.pretty_generate(output))
puts ""
puts "Wrote #{json_path}"
puts "  #{report.summary[:covered]}/#{report.summary[:total]} codepoints (#{report.summary[:pct]}%)"
