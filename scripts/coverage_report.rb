#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage report — for each Unicode 17 block, compute
# assigned-vs-covered codepoints in the built Essenfont-Regular.ttf.
#
# This is the script that reproduces the "53%" number in issue #3 and
# proves coverage improvements.
#
# Block metadata is sourced from ucode's canonical blocks index at
# /Users/mulgogi/src/fontist/ucode/output/blocks/index.json (override
# with --ucode-blocks=PATH). When the path doesn't exist (e.g., ucode
# not built locally), the script falls back to a small inline table
# containing only the blocks declared in the essenfont manifest.
#
# Usage:
#   ruby scripts/coverage_report.rb                    # text report
#   ruby scripts/coverage_report.rb --json             # machine-readable
#   ruby scripts/coverage_report.rb --threshold 95     # flag blocks <95%
#   ruby scripts/coverage_report.rb --font PATH        # custom font path

require "json"
require "optparse"
require "fontisan"

module EssenfontCoverage
  UCODE_BLOCKS_PATH = "/Users/mulgogi/src/fontist/ucode/output/blocks/index.json"

  def self.run(font_path: "Essenfont-Regular.ttf", format: :text,
               threshold: nil, ucode_blocks: nil)
    ucode_blocks ||= UCODE_BLOCKS_PATH

    unless File.exist?(font_path)
      warn "FAIL  #{font_path} not found (run `ruby scripts/build.rb` first)"
      exit 1
    end

    blocks = load_blocks(ucode_blocks)
    cmap_cps = load_font_cmap(font_path)

    report = compute_report(blocks, cmap_cps)

    case format
    when :json then emit_json(report)
    else emit_text(report, font_path, threshold)
    end
  end

  def self.load_blocks(ucode_blocks_path)
    if File.exist?(ucode_blocks_path)
      data = JSON.parse(File.read(ucode_blocks_path))
      data.map { |b| { id: b["id"], first: b["first_cp"], last: b["last_cp"] } }
    else
      warn "  WARN: #{ucode_blocks_path} not found; using inline subset of " \
           "#{UNICODE_BLOCKS_FALLBACK.size} blocks (declare'd in essenfont manifest)"
      UNICODE_BLOCKS_FALLBACK.map { |id, range| { id: id, first: range[0], last: range[1] } }
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
    assigned_rows = rows.reject { |r| reserved_block?(r) }
    reserved_rows = rows.select { |r| reserved_block?(r) }

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
    assigned_rows = rows.reject { |r| reserved_block?(r) }
    reserved_rows = rows.select { |r| reserved_block?(r) }

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

  # Minimal fallback block list (the blocks the essenfont manifest
  # declares covers: for). Only used when ucode's blocks/index.json
  # isn't available.
  UNICODE_BLOCKS_FALLBACK = {
    "Basic_Latin" => [0x0000, 0x007F],
    "Latin-1_Supplement" => [0x0080, 0x00FF],
    "Latin_Extended-A" => [0x0100, 0x017F],
    "Latin_Extended-B" => [0x0180, 0x024F],
    "Greek_and_Coptic" => [0x0370, 0x03FF],
    "Cyrillic" => [0x0400, 0x04FF],
    "CJK_Unified_Ideographs" => [0x4E00, 0x9FFF],
    "CJK_Unified_Ideographs_Extension_B" => [0x20000, 0x2A6DF],
    "CJK_Unified_Ideographs_Extension_G" => [0x30000, 0x3134A],
    "CJK_Unified_Ideographs_Extension_H" => [0x31350, 0x323AF],
    "CJK_Unified_Ideographs_Extension_J" => [0x323B0, 0x3347F],
    "Tangut" => [0x17000, 0x187FF],
    "Egyptian_Hieroglyphs" => [0x13000, 0x1342F],
    "Egyptian_Hieroglyphs_Extended_A" => [0x13460, 0x143FF],
    "Imperial_Aramaic" => [0x10840, 0x1085F],
    "Phoenician" => [0x10900, 0x1091F],
    "Lydian" => [0x10920, 0x1093F],
    "Sidetic" => [0x10940, 0x1095F],
    "Beria_Erfe" => [0x16EA0, 0x16EDF],
    "Tolong_Siki" => [0x11DB0, 0x11DEF],
    "Tai_Yo" => [0x1E6C0, 0x1E6FF],
    "Medefaidrin" => [0x16E40, 0x16E9F],
  }.freeze
end

if __FILE__ == $PROGRAM_NAME
  options = { format: :text, font: "Essenfont-Regular.ttf" }
  OptionParser.new do |opts|
    opts.on("--json", "emit JSON output") { options[:format] = :json }
    opts.on("--font=PATH", "font to inspect") { |v| options[:font] = v }
    opts.on("--threshold=N", Integer, "flag blocks below N%") { |v| options[:threshold] = v }
    opts.on("--ucode-blocks=PATH", "path to ucode blocks/index.json") { |v| options[:ucode_blocks] = v }
  end.parse!

  EssenfontCoverage.run(
    font_path: options[:font],
    format: options[:format],
    threshold: options[:threshold],
    ucode_blocks: options[:ucode_blocks],
  )
end