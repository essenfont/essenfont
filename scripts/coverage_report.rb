#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage report — for each Unicode 17 block, compute
# assigned-vs-covered codepoints in the built Essenfont-Regular.ttf.
#
# This is the script that reproduces the "53%" number in issue #3 and
# proves coverage improvements.
#
# Block metadata comes from the ucode gem (Essenfont::UcodeRef). No
# path overrides needed; ucode ships the canonical 346-block list as
# frozen Ruby constants.
#
# Usage:
#   ruby scripts/coverage_report.rb                    # text report
#   ruby scripts/coverage_report.rb --json             # machine-readable
#   ruby scripts/coverage_report.rb --threshold 95     # flag blocks <95%
#   ruby scripts/coverage_report.rb --font PATH        # custom font path

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "optparse"
require "fontisan"
require "essenfont"

module EssenfontCoverage
  def self.run(font_path: "Essenfont-Regular.ttf", format: :text, threshold: nil)
    unless File.exist?(font_path)
      warn "FAIL  #{font_path} not found (run `ruby scripts/build.rb` first)"
      exit 1
    end

    blocks = load_blocks_from_ucode
    cmap_cps = load_font_cmap(font_path)

    report = compute_report(blocks, cmap_cps)

    case format
    when :json then emit_json(report)
    else emit_text(report, font_path, threshold)
    end
  end

  def self.load_blocks_from_ucode
    catalog = Essenfont::UcodeRef.catalog
    catalog.all_blocks.map do |b|
      { id: b.id, first: b.first_cp, last: b.last_cp }
    end
  end

  def self.load_font_cmap(font_path)
    font = Fontisan::FontLoader.load(font_path)
    cmap = font.table("cmap")
    (cmap.unicode_mappings || {}).keys.to_set
  end

  def self.compute_report(blocks, cmap_cps)
    rows = blocks.map do |b|
      covered = (b[:first]..b[:last]).count { |cp| cmap_cps.include?(cp) }
      total = b[:last] - b[:first] + 1
      pct = total.positive? ? (100.0 * covered / total).round(2) : 0
      {
        id: b[:id],
        range: "U+#{b[:first].to_s(16).upcase}..U+#{b[:last].to_s(16).upcase}",
        first: b[:first],
        last: b[:last],
        covered: covered,
        total: total,
        pct: pct,
        status: pct_status(pct),
      }
    end
    rows.sort_by { |r| -r[:total] }
  end

  def self.pct_status(pct)
    case pct
    when 0 then "EMPTY"
    when 0..50 then "PARTIAL"
    when 50..95 then "MOSTLY"
    when 95..100 then "FULL"
    when 100 then "COMPLETE"
    end
  end

  def self.reserved_block?(row)
    /Private.Use|Surrogates|Specials/i.match?(row[:id])
  end

  def self.emit_text(rows, font_path, threshold)
    reserved_rows, assigned_rows = rows.partition { |r| reserved_block?(r) }

    total_assigned = assigned_rows.sum { |r| r[:total] }
    total_covered = assigned_rows.sum { |r| r[:covered] }
    overall_pct = total_assigned.positive? ? (100.0 * total_covered / total_assigned).round(2) : 0
    empty = assigned_rows.count { |r| r[:covered].zero? }
    complete = assigned_rows.count { |r| r[:covered] == r[:total] }

    puts "=== Coverage report for #{font_path} ==="
    puts ""
    puts "Assigned-block coverage: #{total_covered}/#{total_assigned} codepoints (#{overall_pct}%)"
    puts "(Excludes #{reserved_rows.size} reserved blocks: PUA, Surrogates, Specials —"
    puts " intentionally not coverable by Unicode design.)"
    puts ""
    puts "Blocks: #{assigned_rows.size} assigned (#{complete} complete, #{empty} empty); #{reserved_rows.size} reserved"
    puts ""

    # Column header
    puts "%-44s  %-20s  %10s  %s" % ["Block", "Range", "Covered", "Status"]
    puts "-" * 92

    rows.each do |r|
      marker = threshold && r[:pct] < threshold ? " ⚠" : ""
      puts "%-44s  %-20s  %5d/%-5d  %s (%.2f%%)%s" % [
        r[:id], r[:range], r[:covered], r[:total], r[:status], r[:pct], marker
      ]
    end
    puts ""
    if threshold
      flagged = rows.count { |r| r[:pct] < threshold }
      puts "(flagged #{flagged} blocks below #{threshold}% threshold)"
    end
  end

  def self.emit_json(rows)
    reserved_rows, assigned_rows = rows.partition { |r| reserved_block?(r) }

    out = {
      generated_at: Time.now.utc.iso8601,
      blocks: rows,
      totals: {
        blocks: rows.size,
        assigned_blocks: assigned_rows.size,
        reserved_blocks: reserved_rows.size,
        empty: assigned_rows.count { |r| r[:covered].zero? },
        complete: assigned_rows.count { |r| r[:covered] == r[:total] },
        # Meaningful coverage: assigned chars covered / assigned chars total
        covered: assigned_rows.sum { |r| r[:covered] },
        assigned: assigned_rows.sum { |r| r[:total] },
      },
    }
    puts JSON.pretty_generate(out)
  end

  # Block metadata is sourced from the ucode gem via Essenfont::UcodeRef
  # (always 346 blocks, no fallback needed).
end

if __FILE__ == $PROGRAM_NAME
  options = { format: :text, font: "Essenfont-Regular.ttf" }
  OptionParser.new do |opts|
    opts.on("--json", "emit JSON output") { options[:format] = :json }
    opts.on("--font=PATH", "font to inspect") { |v| options[:font] = v }
    opts.on("--threshold=N", Integer, "flag blocks below N%") { |v| options[:threshold] = v }
  end.parse!

  EssenfontCoverage.run(
    font_path: options[:font],
    format: options[:format],
    threshold: options[:threshold],
  )
end