# frozen_string_literal: true

require "json"
require "fileutils"
require "nokogiri"
require "fontisan"

module Essenfont
  module Release
    # SvgExports: per-codepoint SVG extraction from the built font.
    #
    # Uses fontisan's SvgGenerator (which emits per-glyph unicode= +
    # glyph-name= attributes), then parses the XML and emits one SVG
    # file per codepoint. Optional donor attribution via donor_map.
    module SvgExports
      module_function

      # @param out_dir [String] directory for SVG output
      # @param font_path [String] path to OTC/TTC/TTF
      # @param donor_map [Hash<Integer, Hash>] optional {cp => {label:, license:}}
      def emit(out_dir:, font_path:, donor_map: {})
        raise ArgumentError, "font not found: #{font_path}" unless File.exist?(font_path)

        FileUtils.rm_rf(out_dir)
        FileUtils.mkdir_p(out_dir)

        font = Fontisan::FontLoader.load(font_path)
        units_per_em = font.table("head")&.units_per_em || 1000
        svg_xml = Fontisan::Converters::SvgGenerator.new.convert(font)[:svg_xml]

        doc = Nokogiri::XML(svg_xml)
        glyphs = doc.css("glyph").select { |g| g["unicode"] }

        index = {}
        counts = Hash.new(0)

        glyphs.each do |glyph|
          path_d = glyph["d"]
          if path_d.nil? || path_d.strip.empty?
            counts[:skipped_no_path] += 1
            next
          end

          cps = parse_unicode_attribute(glyph["unicode"])
          if cps.empty?
            counts[:skipped_no_unicode] += 1
            next
          end

          cps.each do |cp|
            hex = cp.to_s(16).upcase
            filename = "U+#{hex}.svg"
            File.write(File.join(out_dir, filename),
                       render_svg(cp, glyph["glyph-name"] || "", path_d, units_per_em, donor_map[cp]))
            index[filename] = {
              cp: "0x#{hex}",
              name: glyph["glyph-name"] || "",
              donor: donor_map[cp] && donor_map[cp][:label]
            }.compact
            counts[:emitted] += 1
          end
        end

        File.write(File.join(out_dir, "index.json"),
                   JSON.pretty_generate(
                     essenfont_version: Essenfont::Otc::Version::STRING,
                     generated_at: Time.now.utc.iso8601,
                     source: font_path,
                     total_svgs: counts[:emitted],
                     files: index
                   ))

        require "zip"
        Zip::File.open("#{out_dir}.zip", Zip::File::CREATE) do |zip|
          Dir.children(out_dir).each { |f| zip.add(f, File.join(out_dir, f)) }
        end

        puts "  SVG exports: #{counts[:emitted]} glyphs"
      end

      def parse_unicode_attribute(text)
        return [] unless text

        decoded = text.gsub(/&#x([0-9A-Fa-f]+);/) { [$1.to_i(16)].pack("U") }
                      .gsub(/&#(\d+);/) { [$1.to_i].pack("U") }
        decoded.codepoints.to_a
      rescue StandardError
        []
      end

      def render_svg(cp, name, path_d, units_per_em, donor_info)
        hex = cp.to_s(16).upcase
        name_meta = name.empty? ? "" : "<name>#{escape_xml(name)}</name>\n          "
        donor_meta = donor_info ? <<-META : ""
          <donor>#{escape_xml(donor_info[:label].to_s)}</donor>
          <license>#{escape_xml(donor_info[:license].to_s)}</license>
        META

        <<~SVG
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{units_per_em} #{units_per_em}" width="#{units_per_em}" height="#{units_per_em}">
            <metadata>
              <codepoint>U+#{hex}</codepoint>
              #{name_meta}#{donor_meta}<essenfont-version>#{Essenfont::Otc::Version::STRING}</essenfont-version>
              <generated-at>#{Time.now.utc.iso8601}</generated-at>
            </metadata>
            <g transform="translate(0, #{units_per_em}) scale(1, -1)">
              <path d="#{path_d}"/>
            </g>
          </svg>
        SVG
      end

      def escape_xml(str)
        str.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end
    end
  end
end
