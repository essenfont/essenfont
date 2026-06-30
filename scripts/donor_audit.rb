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

module EssenfontAudit
  MANIFEST_PATH = File.expand_path("../sources/manifest.yml", __dir__)
  DONOR_DIR = File.expand_path("../references/input-fonts", __dir__)

  # Mirror of build.rb UNICODE_BLOCKS for standalone audit. Keep in
  # sync — or move to a shared module file once a third consumer appears.
  UNICODE_BLOCKS = {
    "Basic_Latin" => [0x0000, 0x007F],
    "Latin-1_Supplement" => [0x0080, 0x00FF],
    "Latin_Extended-A" => [0x0100, 0x017F],
    "Latin_Extended-B" => [0x0180, 0x024F],
    "IPA_Extensions" => [0x0250, 0x02AF],
    "Spacing_Modifier_Letters" => [0x02B0, 0x02FF],
    "Combining_Diacritical_Marks" => [0x0300, 0x036F],
    "Greek_and_Coptic" => [0x0370, 0x03FF],
    "Cyrillic" => [0x0400, 0x04FF],
    "CJK_Unified_Ideographs" => [0x4E00, 0x9FFF],
    "CJK_Symbols_and_Punctuation" => [0x3000, 0x303F],
    "CJK_Radicals_Supplement" => [0x2E80, 0x2EFF],
    "CJK_Strokes" => [0x31C0, 0x31EF],
    "Enclosed_CJK_Letters_and_Months" => [0x3200, 0x32FF],
    "CJK_Unified_Ideographs_Extension_A" => [0x3400, 0x4DBF],
    "CJK_Unified_Ideographs_Extension_B" => [0x20000, 0x2A6DF],
    "CJK_Unified_Ideographs_Extension_C" => [0x2A700, 0x2B73F],
    "CJK_Unified_Ideographs_Extension_D" => [0x2B740, 0x2B81F],
    "CJK_Unified_Ideographs_Extension_E" => [0x2B820, 0x2CEAF],
    "CJK_Unified_Ideographs_Extension_F" => [0x2CEB0, 0x2EBEF],
    "CJK_Unified_Ideographs_Extension_G" => [0x30000, 0x3134A],
    "CJK_Unified_Ideographs_Extension_H" => [0x31350, 0x323AF],
    "CJK_Unified_Ideographs_Extension_J" => [0x323B0, 0x3347F],
    "Sharada" => [0x11180, 0x111CD],
    "Sharada_Supplement" => [0x11B60, 0x11B7F],
    "Tangut" => [0x17000, 0x187FF],
    "Tangut_Components" => [0x18800, 0x18AFF],
    "Tangut_Supplement" => [0x18D00, 0x18D7F],
    "Tolong_Siki" => [0x11DB0, 0x11DEF],
    "Mathematical_Operators" => [0x2200, 0x22FF],
    "Supplemental_Mathematical_Operators" => [0x2A00, 0x2AFF],
    "Mathematical_Alphanumeric_Symbols" => [0x1D400, 0x1D7FF],
    "Miscellaneous_Mathematical_Symbols-A" => [0x27C0, 0x27EF],
    "Miscellaneous_Mathematical_Symbols-B" => [0x2980, 0x29FF],
    "Musical_Symbols" => [0x1D100, 0x1D1FF],
    "Miscellaneous_Symbols" => [0x2600, 0x26FF],
    "Miscellaneous_Technical" => [0x2300, 0x23FF],
    "Alchemical_Symbols" => [0x1F700, 0x1F77F],
    "Miscellaneous_Symbols_and_Pictographs" => [0x1F300, 0x1F5FF],
    "Supplemental_Symbols_and_Pictographs" => [0x1F900, 0x1F9FF],
    "Transport_and_Map_Symbols" => [0x1F680, 0x1F6FF],
    "Chess_Symbols" => [0x1FA00, 0x1FA0F],
    "Symbols_and_Pictographs_Extended-A" => [0x1FA70, 0x1FAFF],
    "Symbols_for_Legacy_Computing" => [0x1FB00, 0x1FBFF],
    "Imperial_Aramaic" => [0x10840, 0x1085F],
    "Phoenician" => [0x10900, 0x1091F],
    "Lydian" => [0x10920, 0x1093F],
    "Sidetic" => [0x10940, 0x1095F],
    "Beria_Erfe" => [0x16EA0, 0x16EDF],
    "Egyptian_Hieroglyphs" => [0x13000, 0x1342F],
    "Egyptian_Hieroglyph_Format_Controls" => [0x13430, 0x1345F],
    "Egyptian_Hieroglyphs_Extended_A" => [0x13460, 0x143FF],
    "Tai_Yo" => [0x16E40, 0x16E9F],
    "Emoticons" => [0x1F600, 0x1F64F],
    "Dingbats" => [0x2700, 0x27BF],
    "Supplemental_Arrows-C" => [0x1F800, 0x1F8FF],
  }.freeze

  VALID_MAGIC = [
    "\x00\x01\x00\x00", # TTF
    "OTTO",              # OTF (CFF)
    "true",              # TrueType (Apple variant)
    "ttcf",              # TTC
    "wOFF",              # WOFF
    "wOF2",              # WOFF2
  ].freeze

  # Run the audit.
  # @param format [Symbol] :text or :json
  # @return [Integer] exit code (0 = all donors OK; 1 = any failures)
  def self.run(format: :text)
    manifest = YAML.safe_load(File.read(MANIFEST_PATH))
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

    # 1. File exists
    path = resolve(file)
    if path.nil?
      result[:ok] = false
      result[:failures] << "file not found at #{file}"
      return result
    end
    result[:file_resolved] = path

    # 2. Valid magic
    magic_ok = valid_font_magic?(path)
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
        covered = cmap_info[:cps].count { |cp| cp >= range[0] && cp <= range[1] }
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

  def self.valid_font_magic?(path)
    return false unless File.exist?(path) && File.size(path) > 16
    magic = File.binread(path, 4)
    return true if VALID_MAGIC.include?(magic)
    return true if magic.getbyte(0) == 0x80 # PFB
    false
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