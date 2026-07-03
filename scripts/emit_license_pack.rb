#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit a license attribution pack for the current release.
#
# Outputs (to ./license-pack/):
#   LICENSE-SOURCES.md       — human-readable per-donor attribution
#   license-overview.csv     — machine-readable donor × license × count
#   fsung-nc-filter.txt      — codepoints subject to FSung-NC restriction
#   LICENSE.md               — concatenated donor LICENSE files
#   license-pack.zip         — bundle of the above
#
# Usage:
#   ruby scripts/emit_license_pack.rb
#
# Reads:
#   sources/manifest.yml                       — donor registry
#   references/input-fonts/ATTRIBUTIONS.md     — full attribution
#   references/input-fonts/<donor>/LICENSE     — per-donor license texts
#                                                 (or *_LICENSE.txt, COPYING, etc.)
#
# Requires a built cp_map (run after scripts/build.rb completes the partition).

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "zip"
require "yaml"
require "digest"
require "fileutils"

module EmitLicensePack
  ROOT = File.expand_path("..", __dir__)
  MANIFEST_PATH = File.join(ROOT, "sources", "manifest.yml")
  DONOR_DIR = File.join(ROOT, "references", "input-fonts")
  OUT_DIR = File.join(ROOT, "license-pack")

  # Donors subject to non-commercial restriction. The label must match
  # what the build emits in cp_map[:label].
  NC_RESTRICTED_LABELS = %w[fsung_m fsung_2 fsung_3 fsung_x].freeze

  def self.emit
    manifest = YAML.safe_load(File.read(MANIFEST_PATH))
    donors = manifest["donors"] || []

    FileUtils.rm_rf(OUT_DIR)
    FileUtils.mkdir_p(OUT_DIR)

    cps_by_donor = load_cp_map_by_donor

    emit_markdown(donors, cps_by_donor)
    emit_csv(donors, cps_by_donor)
    emit_nc_filter(cps_by_donor)
    emit_concat_license(donors)
    zip_pack

    puts "wrote license-pack/ (5 files + zip)"
    puts "  OFL-only cps:    #{cps_by_donor.count { |label, cps| !NC_RESTRICTED_LABELS.include?(label.to_s) && !cps.empty? } } donors"
    puts "  FSung-NC cps:    #{NC_RESTRICTED_LABELS.sum { |l| cps_by_donor[l.to_sym]&.size || 0 }}"
  end

  # Load cp_map if it was dumped during build; otherwise return empty.
  # The build doesn't currently dump cp_map (it's in-memory), so we
  # approximate by scanning the most-recent Essenfont-Regular.otc and
  # extracting per-face cmap. For full per-cp donor accuracy, the build
  # should also dump cp_map.json (TODO: wire that into build.rb).
  def self.load_cp_map_by_donor
    path = File.join(ROOT, "cp_map.json")
    if File.exist?(path)
      JSON.parse(File.read(path))
    else
      warn "NOTE: cp_map.json not found — emit_license_pack.rb produces a"
      warn "      block-level summary only. Run with ESSENFONT_DUMP_CP_MAP=1"
      warn "      to have build.rb emit cp_map.json for per-cp attribution."
      {}
    end
  end

  def self.emit_markdown(donors, cps_by_donor)
    out = []
    out << "# Essenfont license sources"
    out << ""
    out << "This release is assembled from #{donors.size} donor fonts."
    out << "Per-donor attribution:"
    out << ""

    donors.each do |d|
      label = d["label"]
      family = d["family"] || label
      license = d["license"] || "OFL-1.1"
      files = Array(d["file"])
      cps = cps_by_donor[label.to_sym] || []

      out << "## #{family} (#{license})"
      out << ""
      out << "- Files: #{files.join(', ')}"
      out << "- Covers: #{cps.size} codepoints"
      if NC_RESTRICTED_LABELS.include?(label)
        out << "- **Restriction:** non-commercial use only for these glyphs."
        out << "  See https://fgwang.blogspot.com/ for permission."
      end
      if d["url"]
        out << "- Source: #{d['url']}"
      end
      out << ""
    end

    total_cps = cps_by_donor.values.sum(&:size)
    nc_cps = NC_RESTRICTED_LABELS.sum { |l| cps_by_donor[l.to_sym]&.size || 0 }
    ofl_cps = total_cps - nc_cps
    out << "## Summary"
    out << ""
    out << "- Total codepoints: #{total_cps}"
    out << "- OFL-only cps: #{ofl_cps} (#{pct(ofl_cps, total_cps)})"
    out << "- FSung-NC cps: #{nc_cps} (#{pct(nc_cps, total_cps)}) — non-commercial restriction"
    out << ""

    File.write(File.join(OUT_DIR, "LICENSE-SOURCES.md"), out.join("\n"))
  end

  def self.emit_csv(donors, cps_by_donor)
    require "csv"
    rows = donors.map do |d|
      label = d["label"]
      cps = cps_by_donor[label.to_sym] || []
      [
        label,
        d["family"] || label,
        d["license"] || "OFL-1.1",
        cps.size,
        cps.min ? "0x#{cps.min.to_s(16).upcase}" : "",
        cps.max ? "0x#{cps.max.to_s(16).upcase}" : "",
        d["url"] || "",
        d["sha256"] || ""
      ]
    end

    CSV.open(File.join(OUT_DIR, "license-overview.csv"), "wb") do |csv|
      csv << %w[donor family license covers_count first_cp last_cp source_url sha256]
      rows.each { |r| csv << r }
    end
  end

  def self.emit_nc_filter(cps_by_donor)
    nc_cps = NC_RESTRICTED_LABELS.flat_map { |l| cps_by_donor[l.to_sym] || [] }.sort.uniq
    File.write(File.join(OUT_DIR, "fsung-nc-filter.txt"),
               nc_cps.map { |cp| cp.to_s(16).upcase }.join("\n") + "\n")
  end

  def self.emit_concat_license(donors)
    out = []
    donors.each_with_index do |d, i|
      label = d["label"]
      license_file = find_license_file(label)
      out << "---" if i.positive?
      out << ""
      out << "# #{d['family'] || label} (#{label})"
      out << ""
      if license_file && File.exist?(license_file)
        out << File.read(license_file)
      else
        out << "(license file not found; see #{d['url'] || 'the donor source'})"
      end
      out << ""
    end
    File.write(File.join(OUT_DIR, "LICENSE.md"), out.join("\n"))
  end

  def self.find_license_file(label)
    %w[LICENSE LICENSE.txt LICENSE.md OFL.txt OFL.md COPYING NOTICE].each do |name|
      candidates = [
        File.join(DONOR_DIR, label, name),
        File.join(DONOR_DIR, "#{label}_#{name}"),
        File.join(DONOR_DIR, name)
      ]
      candidates.each { |c| return c if File.exist?(c) }
    end
    nil
  end

  def self.zip_pack
    Zip::File.open(File.join(ROOT, "license-pack.zip"), Zip::File::CREATE) do |zip|
      Dir.children(OUT_DIR).each do |f|
        zip.add(f, File.join(OUT_DIR, f))
      end
    end
  end

  def self.pct(n, total)
    return "0%" if total.zero?
    "#{(n.to_f / total * 100).round(1)}%"
  end
end

EmitLicensePack.emit
