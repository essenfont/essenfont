#!/usr/bin/env ruby
# frozen_string_literal: true

# fetch_chart_glyphs.rb — essenfont consumer for ucode's code-chart
# extraction pipeline.
#
# For Unicode blocks with no OFL donor (currently: Sidetic tail,
# Egyptian Hieroglyphs Ext-B), glyphs must come from the Unicode
# Code Chart PDFs. ucode's `code-chart extract` command does the
# PDF → per-codepoint SVG work; this script:
#
#   1. Reads the manifest for `type: code_chart` donor entries
#   2. Invokes `ucode code-chart extract` for each block
#   3. Hands the extracted SVGs to fontisan (SvgToGlyf, when available)
#      to produce a synthetic TTF donor
#   4. Writes the synthetic TTF to references/input-fonts/.generated/
#
# The build's load_donors then loads the synthetic TTF like any
# other donor.
#
# Usage:
#   ruby scripts/fetch_chart_glyphs.rb                  # all code_chart donors
#   ruby scripts/fetch_chart_glyphs.rb --block Sidetic  # one block
#   ruby scripts/fetch_chart_glyphs.rb --list           # list known
#   ruby scripts/fetch_chart_glyphs.rb --dry-run        # plan only
#
# Blocked on:
#   - ucode `code-chart extract` being usable (currently has bugs:
#     block lookup fails for canonical IDs, URL construction uses
#     wrong codepoint). User will notify when fixed.
#   - fontisan `SvgToGlyf` converter (REQ not yet written). When
#     this lands, the synthetize_ttf step below can be implemented.

require "yaml"
require "fileutils"
require "open3"
require "optparse"
require "fontisan"

module EssenfontChartFetch
  MANIFEST_PATH = File.expand_path("../sources/manifest.yml", __dir__)
  GENERATED_DIR = File.expand_path("../references/input-fonts/.generated", __dir__)
  DEFAULT_BLOCKS = %w[Sidetic Egyptian_Hieroglyphs_Extended-B].freeze

  def self.run(blocks: nil, dry_run: false)
    manifest = YAML.safe_load(File.read(MANIFEST_PATH))
    chart_donors = (manifest["donors"] || []).select do |d|
      d["type"] == "code_chart" &&
        (blocks.nil? || blocks.include?(d["block"]))
    end

    if chart_donors.empty?
      warn "no code_chart donors in manifest#{blocks ? " matching #{blocks.inspect}" : ""}"
      return
    end

    FileUtils.mkdir_p(GENERATED_DIR) unless dry_run

    chart_donors.each do |donor|
      puts "=== #{donor["label"]} (#{donor["block"]}) ==="
      block = donor["block"]
      staging = File.join(GENERATED_DIR, "chart-svg", block.tr("-", "_"))
      synthetic_ttf = File.join(GENERATED_DIR, "#{block.tr("-", "_")}.ttf")

      if dry_run
        puts "  [plan] ucode code-chart extract --block #{block} --to #{staging}"
        puts "  [plan] fontisan SvgToGlyf → #{synthetic_ttf}"
        next
      end

      begin
        extract_via_ucode(block, staging)
        synthetize_ttf(staging, synthetic_ttf, block)
        puts "  synthetic donor: #{synthetic_ttf}"
      rescue StandardError => e
        warn "  FAIL: #{e.class}: #{e.message}"
        warn "  (ucode/fontisan upstream may not be ready; see TODO.full/04)"
      end
    end
  end

  def self.extract_via_ucode(block, staging)
    FileUtils.rm_rf(staging)
    FileUtils.mkdir_p(staging)

    cmd = ["bundle", "exec", "ucode", "code-chart", "extract",
           "--block", block, "--to", staging]
    stdout, status = Open3.capture2(*cmd)
    unless status.success?
      raise "ucode extract failed:\n#{stdout}"
    end

    svg_dir = File.join(staging, block.tr("-", "_"))
    svgs = Dir.glob("#{svg_dir}/U+*.svg")
    if svgs.empty?
      raise "ucode produced no SVGs in #{svg_dir} (pipeline not ready?)"
    end
    puts "  extracted #{svgs.size} SVGs"
  end

  # Convert SVGs → synthetic TTF using fontisan's SvgToGlyf.
  # Blocked on fontisan SvgToGlyf REQ being implemented.
  def self.synthetize_ttf(staging, output_path, block)
    svg_dir = File.join(staging, block.tr("-", "_"))
    svgs = Dir.glob("#{svg_dir}/U+*.svg").sort

    unless defined?(Fontisan::SvgToGlyf)
      raise "Fontisan::SvgToGlyf not defined — install fontisan with the SvgToGlyf feature"
    end

    builder = Fontisan::FontBuilder.new(format: :ttf)
    svgs.each do |svg_path|
      cp = parse_codepoint(File.basename(svg_path, ".svg"))
      svg_data = File.read(svg_path)
      glyf = Fontisan::SvgToGlyf.convert(svg_data, upm: 1000)
      builder.add_glyph(cp, glyf)
    end

    builder.write_to(output_path)
  end

  def self.parse_codepoint(filename)
    filename.sub(/^U\+/, "").to_i(16)
  end

  def self.list_known_blocks
    puts "Code-chart-extraction candidates (blocks with no OFL donor):"
    DEFAULT_BLOCKS.each do |b|
      url = "https://www.unicode.org/charts/PDF/U#{block_start(b).to_s(16).upcase}.pdf"
      puts "  #{b}  →  #{url}"
    end
  end

  # Range info for known blocks (avoids ucode roundtrip for --list).
  def self.block_start(block_id)
    {
      "Sidetic" => 0x10940,
      "Egyptian_Hieroglyphs_Extended-B" => 0x16A40,
    }[block_id] || 0
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { blocks: nil, dry_run: false }
  OptionParser.new do |opts|
    opts.banner = "Usage: fetch_chart_glyphs.rb [options]"
    opts.on("--block=BLOCK", "only fetch the named block (repeatable)") { |v| (options[:blocks] ||= []) << v }
    opts.on("--dry-run", "show plan without invoking ucode/fontisan") { options[:dry_run] = true }
    opts.on("--list", "list known code_chart blocks") do
      EssenfontChartFetch.list_known_blocks
      exit 0
    end
  end.parse!

  EssenfontChartFetch.run(blocks: options[:blocks], dry_run: options[:dry_run])
end