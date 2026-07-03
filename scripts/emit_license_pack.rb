#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit a license attribution pack for the current release.
#
# Uses Essenfont::Manifest for the donor registry (no inline YAML).

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "zip"
require "csv"
require "json"
require "essenfont"

module EmitLicensePack
  ROOT = File.expand_path("..", __dir__)
  DONOR_DIR = File.join(ROOT, "references", "input-fonts")
  OUT_DIR = File.join(ROOT, "license-pack")

  NC_RESTRICTED_LABELS = %i[fsung_m fsung_2 fsung_3 fsung_x].freeze

  module_function

  def emit
    manifest = Essenfont::Manifest.load
    cps_by_donor = load_cps_by_donor

    require "fileutils"
    FileUtils.rm_rf(OUT_DIR)
    FileUtils.mkdir_p(OUT_DIR)

    emit_markdown(manifest, cps_by_donor)
    emit_csv(manifest, cps_by_donor)
    emit_nc_filter(cps_by_donor)
    emit_concat_license(manifest)
    zip_pack

    total_cps = cps_by_donor.values.sum(&:size)
    nc_cps = NC_RESTRICTED_LABELS.sum { |l| cps_by_donor[l]&.size || 0 }

    puts "wrote license-pack/ (5 files + zip)"
    puts "  donors:    #{manifest.size}"
    puts "  total cps: #{total_cps}"
    puts "  FSung-NC:  #{nc_cps}"
  end

  def self.load_cps_by_donor
    path = File.join(ROOT, "cp_map.json")
    unless File.exist?(path)
      warn "NOTE: cp_map.json not found — block-level summary only. " \
           "Run build.rb with ESSENFONT_DUMP_CP_MAP=1 for per-cp attribution."
      return {}
    end

    JSON.parse(File.read(path))
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(cp_str, info), h|
      h[info["label"].to_sym] << cp_str.to_i(16)
    end
  end
  private_class_method :load_cps_by_donor

  def self.emit_markdown(manifest, cps_by_donor)
    out = []
    out << "# Essenfont license sources"
    out << ""
    out << "Assembled from #{manifest.size} donor fonts. Per-donor attribution:"
    out << ""

    manifest.each do |entry|
      cps = cps_by_donor[entry.label] || []
      out << "## #{entry.family} (#{entry.license})"
      out << ""
      out << "- Files: #{Array(entry.file).join(', ')}"
      out << "- Covers: #{cps.size} codepoints"
      if NC_RESTRICTED_LABELS.include?(entry.label)
        out << "- **Restriction:** non-commercial use only for these glyphs."
        out << "  See https://fgwang.blogspot.com/ for permission."
      end
      out << "- Source: #{entry.url}" if entry.url
      out << ""
    end

    total_cps = cps_by_donor.values.sum(&:size)
    nc_cps = NC_RESTRICTED_LABELS.sum { |l| cps_by_donor[l]&.size || 0 }
    ofl_cps = total_cps - nc_cps
    out << "## Summary"
    out << ""
    out << "- Total codepoints: #{total_cps}"
    out << "- OFL-only cps: #{ofl_cps} (#{pct(ofl_cps, total_cps)})"
    out << "- FSung-NC cps: #{nc_cps} (#{pct(nc_cps, total_cps)}) — non-commercial restriction"
    out << ""

    File.write(File.join(OUT_DIR, "LICENSE-SOURCES.md"), out.join("\n"))
  end
  private_class_method :emit_markdown

  def self.emit_csv(manifest, cps_by_donor)
    CSV.open(File.join(OUT_DIR, "license-overview.csv"), "wb") do |csv|
      csv << %w[donor family license covers_count first_cp last_cp source_url sha256]
      manifest.each do |entry|
        cps = cps_by_donor[entry.label] || []
        csv << [
          entry.label, entry.family, entry.license, cps.size,
          cps.min ? "0x#{cps.min.to_s(16).upcase}" : "",
          cps.max ? "0x#{cps.max.to_s(16).upcase}" : "",
          entry.url || "", entry.sha256 || ""
        ]
      end
    end
  end
  private_class_method :emit_csv

  def self.emit_nc_filter(cps_by_donor)
    nc_cps = NC_RESTRICTED_LABELS.flat_map { |l| cps_by_donor[l] || [] }.sort.uniq
    File.write(File.join(OUT_DIR, "fsung-nc-filter.txt"),
               nc_cps.map { |cp| cp.to_s(16).upcase }.join("\n") + "\n")
  end
  private_class_method :emit_nc_filter

  def self.emit_concat_license(manifest)
    out = []
    manifest.each_with_index do |entry, i|
      license_file = find_license_file(entry.label)
      out << "---" if i.positive?
      out << ""
      out << "# #{entry.family} (#{entry.label})"
      out << ""
      if license_file && File.exist?(license_file)
        out << File.read(license_file)
      else
        out << "(license file not found; see #{entry.url || 'the donor source'})"
      end
      out << ""
    end
    File.write(File.join(OUT_DIR, "LICENSE.md"), out.join("\n"))
  end
  private_class_method :emit_concat_license

  def self.find_license_file(label)
    label_str = label.to_s
    %w[LICENSE LICENSE.txt LICENSE.md OFL.txt OFL.md COPYING NOTICE].each do |name|
      [
        File.join(DONOR_DIR, label_str, name),
        File.join(DONOR_DIR, "#{label_str}_#{name}"),
        File.join(DONOR_DIR, name)
      ].each { |c| return c if File.exist?(c) }
    end
    nil
  end
  private_class_method :find_license_file

  def self.zip_pack
    Zip::File.open(File.join(ROOT, "license-pack.zip"), Zip::File::CREATE) do |zip|
      Dir.children(OUT_DIR).each { |f| zip.add(f, File.join(OUT_DIR, f)) }
    end
  end
  private_class_method :zip_pack

  def self.pct(n, total)
    return "0%" if total.zero?

    "#{(n.to_f / total * 100).round(1)}%"
  end
  private_class_method :pct
end

EmitLicensePack.emit
