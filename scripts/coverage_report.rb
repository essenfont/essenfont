#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage report — for each Unicode 17 block, compute
# assigned-vs-covered codepoints in the built Essenfont font.
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
  module_function

  def run(font_path:, format:, threshold:)
    unless File.exist?(font_path)
      warn "FAIL  #{font_path} not found (run `ruby scripts/build.rb` first)"
      exit 1
    end

    cmap_cps = load_font_cmap(font_path)
    report = Essenfont::Coverage::Report.new(cmap_cps)

    case format
    when :json then emit_json(report)
    else emit_text(report, font_path, threshold)
    end
  end

  def load_font_cmap(font_path)
    font = Fontisan::FontLoader.load(font_path)
    cmap = font.table("cmap")
    (cmap&.unicode_mappings || {}).keys
  end

  def emit_text(report, font_path, threshold)
    rows = report.per_block
    summary = report.summary

    puts "=== Coverage report for #{font_path} ==="
    puts ""
    puts "Assigned-block coverage: #{summary[:covered]}/#{summary[:total]} codepoints (#{summary[:pct]}%)"
    puts "(Excludes #{summary[:reserved_blocks]} reserved blocks: PUA, Surrogates, Specials —"
    puts " intentionally not coverable by Unicode design.)"
    puts ""
    puts "Blocks: #{summary[:assigned_blocks]} assigned (#{summary[:complete]} complete, #{summary[:empty]} empty); #{summary[:reserved_blocks]} reserved"
    puts ""
    puts "%-44s  %-20s  %10s  %s" % ["Block", "Range", "Covered", "Status"]
    puts "-" * 92

    rows.each do |r|
      marker = threshold && r[:pct] < threshold ? " ⚠" : ""
      puts "%-44s  %-20s  %5d/%-5d  %s (%.2f%%)%s" % [
        r[:id], r[:range], r[:covered], r[:total], r[:status], r[:pct], marker
      ]
    end
    puts ""
    return unless threshold

    flagged = rows.count { |r| r[:pct] < threshold }
    puts "(flagged #{flagged} blocks below #{threshold}% threshold)"
  end

  def emit_json(report)
    puts JSON.pretty_generate(
      generated_at: Time.now.utc.iso8601,
      blocks: report.per_block,
      totals: report.summary
    )
  end
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
    threshold: options[:threshold]
  )
end
