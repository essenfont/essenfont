# frozen_string_literal: true

require "json"
require "csv"
require "fileutils"
require "zip"

module Essenfont
  module Release
    # LicensePack: OFL attribution pack for the assembled font.
    #
    # Emits LICENSE-SOURCES.md (per-donor summary), license-overview.csv,
    # fsung-nc-filter.txt (non-commercial codepoint list), LICENSE.md
    # (concatenated donor licenses), and license-pack.zip.
    module LicensePack
      NC_RESTRICTED_LABELS = %i[fsung_m fsung_2 fsung_3 fsung_x].freeze

      module_function

      # @param out_dir [String] release output directory
      # @param cp_map [Essenfont::CpMap, nil] codepoint→donor map (nil = block-only summary)
      def emit(out_dir:, cp_map: nil)
        pack_dir = File.join(out_dir, "license-pack")
        FileUtils.mkdir_p(pack_dir)

        manifest = Essenfont::Manifest.load
        cps_by_donor = group_codepoints_by_donor(cp_map)
        donor_dir = File.expand_path("../../references/input-fonts", __dir__)

        emit_markdown(pack_dir, manifest, cps_by_donor)
        emit_csv(pack_dir, manifest, cps_by_donor)
        emit_nc_filter(pack_dir, cps_by_donor)
        emit_concat_license(pack_dir, manifest, donor_dir)
        zip_pack(out_dir, pack_dir)

        total_cps = cps_by_donor.values.sum(&:size)
        nc_cps = NC_RESTRICTED_LABELS.sum { |l| cps_by_donor[l]&.size || 0 }
        puts "  license-pack: #{manifest.size} donors, #{nc_cps} NC cps"
      end

      def group_codepoints_by_donor(cp_map)
        return {} unless cp_map

        cp_map.donor_labels.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(cp, label), h|
          h[label] << cp
        end
      end

      def emit_markdown(pack_dir, manifest, cps_by_donor)
        out = ["# Essenfont license sources", "", "Assembled from #{manifest.size} donor fonts. Per-donor attribution:", ""]

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

        File.write(File.join(pack_dir, "LICENSE-SOURCES.md"), out.join("\n"))
      end

      def emit_csv(pack_dir, manifest, cps_by_donor)
        CSV.open(File.join(pack_dir, "license-overview.csv"), "wb") do |csv|
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

      def emit_nc_filter(pack_dir, cps_by_donor)
        nc_cps = NC_RESTRICTED_LABELS.flat_map { |l| cps_by_donor[l] || [] }.sort.uniq
        File.write(File.join(pack_dir, "fsung-nc-filter.txt"),
                   nc_cps.map { |cp| cp.to_s(16).upcase }.join("\n") + "\n")
      end

      def emit_concat_license(pack_dir, manifest, donor_dir)
        out = []
        manifest.each_with_index do |entry, i|
          license_file = find_license_file(donor_dir, entry.label)
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
        File.write(File.join(pack_dir, "LICENSE.md"), out.join("\n"))
      end

      def find_license_file(donor_dir, label)
        label_str = label.to_s
        %w[LICENSE LICENSE.txt LICENSE.md OFL.txt OFL.md COPYING NOTICE].each do |name|
          [
            File.join(donor_dir, label_str, name),
            File.join(donor_dir, "#{label_str}_#{name}"),
            File.join(donor_dir, name)
          ].each { |c| return c if File.exist?(c) }
        end
        nil
      end

      def zip_pack(out_dir, pack_dir)
        Zip::File.open(File.join(out_dir, "license-pack.zip"), Zip::File::CREATE) do |zip|
          Dir.children(pack_dir).each { |f| zip.add(f, File.join(pack_dir, f)) }
        end
      end

      def pct(n, total)
        return "0%" if total.zero?

        "#{(n.to_f / total * 100).round(1)}%"
      end
    end
  end
end
