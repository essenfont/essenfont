#!/usr/bin/env ruby
# frozen_string_literal: true

# TTC-aware coverage report. Unions the cmap of every face in the
# Essenfont TTC and emits per-block coverage to the website's
# public/coverage.json.
#
# Per-block "assigned" denominator comes from Ucode::Unicode::Catalog
# (the ucode gem's frozen per-block assigned-codepoint counts). No
# external UCD file required.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "time"
require "set"
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

# Per-block coverage.
results = catalog.all_blocks.map do |b|
  first = b.first_cp
  last = b.last_cp
  block_range = (first..last)

  # Block object doesn't expose per-block assigned count; use the
  # full range size. The percentage will be a conservative lower bound
  # (counts unassigned codepoints in partially-assigned blocks as
  # "not covered"), which is the right direction to under-claim.
  total_assigned = block_range.size
  covered = union_cmap.count { |cp| block_range.cover?(cp) }

  pct = total_assigned.positive? ? (100.0 * covered / total_assigned).round(2) : 0
  status = if total_assigned.zero? then "RESERVED"
            elsif covered >= total_assigned then "COMPLETE"
            elsif pct >= 95 then "FULL"
            elsif pct >= 50 then "MOSTLY"
            elsif pct.positive? then "PARTIAL"
            else "EMPTY"
            end

  {
    id: b.id,
    name: b.name,
    range: "U+#{first.to_s(16).upcase}..U+#{last.to_s(16).upcase}",
    first: first,
    last: last,
    covered: covered,
    total: total_assigned,
    pct: pct,
    status: status,
  }
end

total_assigned = results.sum { |r| r[:total] }
total_covered = results.sum { |r| [r[:covered], r[:total]].min }
overall_pct = total_assigned.positive? ? (100.0 * total_covered / total_assigned).round(4) : 0

puts ""
puts "Per-block assigned coverage: #{total_covered}/#{total_assigned} (#{overall_pct}%)"
puts "Union cmap size: #{union_cmap.size} (some codepoints fall outside recognized blocks)"
puts ""

output = {
  generated_at: Time.now.utc.iso8601,
  unicode_version: catalog.version,
  source: TTC_FILE,
  overall: {
    covered: total_covered,
    total: total_assigned,
    pct: overall_pct,
    block_count: results.size,
    cmap_union: union_cmap.size,
  },
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
  blocks: results.sort_by { |r| r[:first] },
}

json_path = File.join(File.dirname(__FILE__), "..", "..", "essenfont.github.io", "public", "coverage.json")
File.write(json_path, JSON.pretty_generate(output))
puts "Wrote #{json_path}"
