#!/usr/bin/env ruby
# frozen_string_literal: true

# Update coverage_report.rb to use rigorous UCD-based denominator.
# Counts only ASSIGNED character codepoints (Cc, Cf, L*, M*, N*,
# P*, S*, Z* per DerivedGeneralCategory.txt) — excludes Cs, Co, Cn.

require "json"
require "fontisan"

GEN_CAT_FILE = "/tmp/gen-cat.txt"
FONT_FILE = ARGV[0] || "Essenfont-Regular.ttf"
UCODE_BLOCKS = "/Users/mulgogi/src/fontist/ucode/output/blocks/index.json"

# Parse general categories
cat_ranges = Hash.new { |h, k| h[k] = [] }
File.foreach(GEN_CAT_FILE) do |line|
  next if line =~ /^#/ || line.strip.empty?
  if line =~ /^([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?\s*;\s*(\w+)/
    first = $1.to_i(16)
    last = $2 ? $2.to_i(16) : first
    cat_ranges[$3] << (first..last)
  end
end

CHARACTER_CATS = %w[Cc Cf Ll Lm Lo Lt Lu Mc Me Mn Nd Nl No Pc Pd Pe Pf Pi Po Ps Sc Sk Sm So Zl Zp Zs]
character_ranges = CHARACTER_CATS.flat_map { |c| cat_ranges[c] || [] }

# Load font
font = Fontisan::FontLoader.load(FONT_FILE)
cmap = font.table("cmap").unicode_mappings&.keys || []

# Load block metadata from ucode
blocks = JSON.parse(File.read(UCODE_BLOCKS))

# For each block, compute:
# - total_assigned = count of codepoints in block that are character cats
# - covered = count of our cmap entries in block that are character cats
results = blocks.map do |b|
  first = b["first_cp"]
  last = b["last_cp"]
  block_range = (first..last)

  total_assigned = (first..last).count { |cp| character_ranges.any? { |r| r.cover?(cp) } }
  covered = cmap.count { |cp| block_range.cover?(cp) && character_ranges.any? { |r| r.cover?(cp) } }

  pct = total_assigned.positive? ? (100.0 * covered / total_assigned).round(2) : 0
  status = if total_assigned.zero? then "RESERVED"
            elsif covered == total_assigned then "COMPLETE"
            elsif pct >= 95 then "FULL"
            elsif pct >= 50 then "MOSTLY"
            elsif pct > 0 then "PARTIAL"
            else "EMPTY"
            end

  {
    id: b["id"],
    name: b["name"],
    range: "U+#{first.to_s(16).upcase}..U+#{last.to_s(16).upcase}",
    first: first,
    last: last,
    covered: covered,
    total: total_assigned,
    pct: pct,
    status: status,
  }
end

# Totals (assigned characters only, excluding PUA/Surrogate/Specials/Cn)
total_assigned = results.sum { |r| r[:total] }
total_covered = results.sum { |r| r[:covered] }
overall_pct = total_assigned.positive? ? (100.0 * total_covered / total_assigned).round(4) : 0

puts "=== Coverage report for #{FONT_FILE} ==="
puts ""
puts "Assigned character coverage: #{total_covered}/#{total_assigned} (#{overall_pct}%)"
puts ""
puts "Excludes: PUA, Surrogates, Specials, unassigned codepoints within blocks"
puts ""

# JSON output
output = {
  generated_at: Time.now.utc.iso8601,
  blocks: results.sort_by { |r| r[:first] },
  totals: {
    blocks: results.size,
    assigned_blocks: results.count { |r| r[:status] != "RESERVED" },
    reserved_blocks: results.count { |r| r[:status] == "RESERVED" },
    empty: results.count { |r| r[:status] == "EMPTY" },
    complete: results.count { |r| r[:status] == "COMPLETE" || r[:status] == "FULL" },
    covered: total_covered,
    assigned: total_assigned,
    pct: overall_pct,
  },
}

json_path = File.join(File.dirname(__FILE__), "..", "..", "essenfont.github.io", "public", "coverage.json")
File.write(json_path, JSON.pretty_generate(output))
puts "Wrote #{json_path}"
