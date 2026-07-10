#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage report with rigorous UCD-based denominator.
# Counts only ASSIGNED character codepoints (Cc, Cf, L*, M*, N*,
# P*, S*, Z* per DerivedGeneralCategory.txt) — excludes Cs, Co, Cn.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "fontisan"
require "essenfont"

GEN_CAT_FILE = "/tmp/gen-cat.txt"
FONT_FILE = ARGV[0] || "Essenfont-Regular.ttf"

catalog = Essenfont::UcodeRef.catalog

# Parse general categories from DerivedGeneralCategory.txt
cat_ranges = Hash.new { |h, k| h[k] = [] }
File.foreach(GEN_CAT_FILE) do |line|
  next if line =~ /^#/ || line.strip.empty?

  if line =~ /^([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?\s*;\s*(\w+)/
    first = $1.to_i(16)
    last = $2 ? $2.to_i(16) : first
    cat_ranges[$3] << (first..last)
  end
end

CHARACTER_CATS = %w[Cc Cf Ll Lm Lo Lt Lu Mc Me Mn Nd Nl No Pc Pd Pe Pf Pi Po Ps Sc Sk Sm So Zl Zp Zs].freeze
character_ranges = CHARACTER_CATS.flat_map { |c| cat_ranges[c] || [] }

# Build a Set of assigned codepoints for the Report's assigned_filter.
assigned_set = Set.new
character_ranges.each { |r| r.each { |cp| assigned_set << cp } }

# Load font cmap
font = Fontisan::FontLoader.load(FONT_FILE)
cmap_cps = font.table("cmap").unicode_mappings&.keys || []

report = Essenfont::Coverage::Report.new(cmap_cps, catalog: catalog, assigned_filter: assigned_set)

puts "=== Coverage report for #{FONT_FILE} ==="
puts ""
puts "Assigned character coverage: #{report.summary[:covered]}/#{report.summary[:total]} (#{report.summary[:pct]}%)"
puts ""
puts "Excludes: PUA, Surrogates, Specials, unassigned codepoints within blocks"
puts ""

output = {
  generated_at: Time.now.utc.iso8601,
  blocks: report.per_block,
  totals: report.summary
}

json_path = File.join(File.dirname(__FILE__), "..", "..", "essenfont.github.io", "public", "coverage.json")
File.write(json_path, JSON.pretty_generate(output))
puts "Wrote #{json_path}"
