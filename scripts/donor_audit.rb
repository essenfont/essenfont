#!/usr/bin/env ruby
# frozen_string_literal: true

# Donor audit script — reads sources/manifest.yml and validates every
# declared donor against its actual state on disk + cmap coverage.
#
# Checks:
#  1. File exists at the declared path
#  2. File is a valid font (not HTML)
#  3. SHA256 matches manifest (unless "TBD" or nil)
#  4. cmap size is reported
#  5. For each declared covers: block, compute actual cmap coverage
#     in that block's Unicode range
#  6. Flag donors with 0% coverage of any declared block (would be
#     caught by the build's coverage gate; this is the pre-flight tool)
#  7. Detect cmap format 13 (LastResort-style) — fontisan returns 0
#     entries, silently producing a "loaded" font that contributes
#     nothing to the build
#
# Usage:
#   ruby scripts/donor_audit.rb
#   ruby scripts/donor_audit.rb --json    # machine-readable output

require "yaml"
require "digest"
require "json"
require "optparse"
require "fontisan"
require "essenfont"

module EssenfontAudit
  MANIFEST_PATH = File.expand_path("../sources/manifest.yml", __dir__)
  DONOR_DIR = File.expand_path("../references/input-fonts", __dir__)

  # Load Unicode 17 block ranges from the ucode gem (no path concerns).
  def self.load_unicode_blocks
    Essenfont::UcodeRef.block_ranges
  end

  UNICODE_BLOCKS = load_unicode_blocks.freeze

  # Run the audit.
  # @param format [Symbol] :text or :json
  # @return [Integer] exit code (0 = all donors OK; 1 = any failures)
  def self.run(format: :text)
    manifest = YAML.safe_load_file(MANIFEST_PATH)
    donors = manifest["donors"] || []

    results = donors.map { |entry| audit_donor(entry) }
    failures = results.count { |r| !r[:ok] }

    if format == :json
      puts JSON.pretty_generate({ donors: results, failure_count: failures })
    else
      print_text(results, failures)
    end

    failures.zero? ? 0 : 1
  end

  # @return [Hash] {label, ok, file, sha256_match, magic_ok, cmap_size,
  #                  covers_status, notes}
  def self.audit_donor(entry)
    label = entry["label"]
    file = entry["file"]
    enabled = entry["enabled"] != false
    expected_sha = entry["sha256"]
    declared_covers = entry["covers"] || []

    result = {
      label: label,
      ok: true,
      file: file,
      enabled: enabled,
      failures: [],
    }

    unless enabled
      result[:notes] = "disabled in manifest (enabled: false)"
      return result
    end

    # code_chart donors are synthetic; report as deferred until the
    # synthetic TTF exists.
    if entry["type"] == "code_chart"
      generated_dir = File.expand_path("../references/input-fonts/.generated", __dir__)
      synthetic = File.join(generated_dir, "#{entry["block"].tr("-", "_")}.ttf")
      if File.exist?(synthetic)
        file = synthetic
      else
        result[:notes] = "type: code_chart — synthetic TTF not yet generated"
        return result
      end
    end

    # 1. File exists
    path = resolve(file)
    if path.nil?
      result[:ok] = false
      result[:failures] << "file not found at #{file}"
      return result
    end
    result[:file_resolved] = path

    # 2. Valid magic
    magic_ok = Essenfont::FontMagic.valid?(path)
    result[:magic_ok] = magic_ok
    unless magic_ok
      result[:ok] = false
      result[:failures] << "not a valid font file (HTML or corrupted)"
      return result
    end

    # 3. SHA256 match
    if expected_sha && expected_sha != "TBD"
      actual_sha = Digest::SHA256.file(path).hexdigest
      result[:sha256_expected] = expected_sha
      result[:sha256_actual] = actual_sha
      if actual_sha != expected_sha.downcase
        result[:ok] = false
        result[:failures] << "sha256 mismatch (expected #{expected_sha[0..15]}…, got #{actual_sha[0..15]}…)"
      end
    else
      result[:sha256_expected] = expected_sha || "(nil)"
      result[:sha256_skipped] = "TBD or nil — not verified"
    end

    # 4. cmap size (this may fail for some fonts; soft-fail)
    cmap_info = probe_cmap(path)
    result[:cmap_size] = cmap_info[:size]
    result[:cmap_warning] = cmap_info[:warning]
    if cmap_info[:size].zero? && cmap_info[:warning]
      result[:ok] = false
      result[:failures] << cmap_info[:warning]
      return result
    end

    # 4b. Apply codepoint_remap if declared (rewrites cmap cps before
    # coverage gate so the gate sees the *target* Unicode block).
    remap = Essenfont::Remap.load(entry["codepoint_remap"],
                                  search_dirs: [File.join(DONOR_DIR, "..", "..")])
    if remap
      original_size = cmap_info[:cps].size
      cmap_info[:cps] = cmap_info[:cps].each_with_object({}) do |cp, h|
        target = remap[cp]
        h[target] = true if target
      end.keys
      result[:remapped_from] = original_size
      result[:remapped_to] = cmap_info[:cps].size
      result[:cmap_size] = cmap_info[:cps].size
    end

    # 5. Coverage of declared covers: blocks
    result[:covers] = declared_covers.map do |block|
      range = UNICODE_BLOCKS[block]
      if range.nil?
        {
          block: block,
          status: "UNKNOWN_BLOCK",
          note: "not in UNICODE_BLOCKS; add it (and verify the range)",
        }
      else
        covered = cmap_info[:cps].count { |cp| cp.between?(range[0], range[1]) }
        total = range[1] - range[0] + 1
        {
          block: block,
          range: "U+#{range[0].to_s(16).upcase}..U+#{range[1].to_s(16).upcase}",
          covered: covered,
          total: total,
          pct: total.positive? ? (100.0 * covered / total).round(2) : 0,
          status: covered.zero? ? "FAIL" : "OK",
        }.tap do |h|
          if covered.zero?
            result[:ok] = false
            result[:failures] << "covers:#{block} has 0 cmap coverage"
          end
        end
      end
    end

    result
  end

  # Probe the font's cmap. Returns {size: Integer, cps: Set<Integer>,
  # warning: String|nil}.
  def self.probe_cmap(path)
    font = Fontisan::FontLoader.load(path)
    cmap = font.table("cmap")
    if cmap.nil?
      return { size: 0, cps: [], warning: "no cmap table" }
    end
    cps = cmap.unicode_mappings&.keys || []
    if cps.empty?
      warning = "cmap has 0 entries (fontisan may not support this cmap " \
                "format — e.g., LastResortHE uses format 13)"
      return { size: 0, cps: [], warning: warning }
    end
    { size: cps.size, cps: cps, warning: nil }
  end

  def self.resolve(file)
    return file if File.exist?(file)
    candidate = File.join(DONOR_DIR, File.basename(file))
    return candidate if File.exist?(candidate)
    nil
  end

  def self.print_text(results, failures)
    puts "=== Donor audit (manifest: #{MANIFEST_PATH}) ==="
    puts ""
    results.each do |r|
      status = r[:ok] ? "OK  " : "FAIL"
      enabled_note = r[:enabled] ? "" : " [DISABLED]"
      puts "[#{status}] #{r[:label]}#{enabled_note}"
      puts "       file: #{r[:file_resolved] || r[:file]}"
      r[:failures].each { |f| puts "       ✗ #{f}" }
      if r[:covers] && !r[:covers].empty?
        r[:covers].each do |c|
          if c[:status] == "OK"
            line = "       ✓ covers:#{c[:block]} #{c[:covered]}/#{c[:total]} cps (#{c[:pct]}%)"
          elsif c[:status] == "FAIL"
            line = "       ✗ covers:#{c[:block]} 0/#{c[:total]} cps"
          else
            line = "       ? covers:#{c[:block]} (UNKNOWN — add to UNICODE_BLOCKS)"
          end
          puts line
        end
      end
      puts "       cmap size: #{r[:cmap_size]}" if r[:cmap_size]
      puts "       #{r[:sha256_skipped]}" if r[:sha256_skipped]
      puts "       #{r[:notes]}" if r[:notes]
      puts ""
    end
    puts "=== Summary: #{failures} donor(s) with failures ==="
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { format: :text }
  OptionParser.new do |opts|
    opts.on("--json", "emit JSON output") { options[:format] = :json }
  end.parse!

  exit EssenfontAudit.run(format: options[:format])
end