# frozen_string_literal: true

module Essenfont
  module Otc
    class Build
      Result = Struct.new(:output_path, :bytes, :subfonts, :subfont_count,
                          keyword_init: true)

      DEFAULT_SUBFONT_FORMAT = :ttf
      DEFAULT_FAMILY = Naming::FAMILY

      attr_reader :cp_map, :donors, :subfont_format, :partitioner, :family,
                  :version

      def initialize(cp_map:, donors:, subfont_format: DEFAULT_SUBFONT_FORMAT,
                     partitioner: default_partitioner,
                     family: DEFAULT_FAMILY, version: Naming.version_string)
        unless cp_map.is_a?(Hash) || cp_map.is_a?(Essenfont::CpMap)
          raise ArgumentError, "cp_map must be a Hash or CpMap, got #{cp_map.class}"
        end
        unless donors.is_a?(Hash)
          raise ArgumentError, "donors must be a Hash, got #{donors.class}"
        end

        @cp_map = coerce_cp_map(cp_map)
        @donors = donors
        @subfont_format = subfont_format
        @partitioner = partitioner
        @family = family
        @version = version
      end

      def call(output_path:)
        blueprint = partitioner.call(cp_map.donor_labels)
        stitcher = Fontisan::Stitcher.new
        donors.each_value do |d|
          stitcher.add_source(d.label, d.outline_source, remap: d.remap)
        end
        stitcher.set_info(base_info_values)

        blueprint.apply_to(stitcher)

        collection = stitcher.write_collection(output_path, format: subfont_format)

        MetricsPass.recompute!(collection.path)

        Result.new(
          output_path: collection.path,
          bytes: collection.bytes,
          subfonts: collection.subfonts.map(&:to_h),
          subfont_count: collection.face_count
        )
      end

      # Write per-plane TTFs (one file per Unicode plane). Returns an
      # Array of {name:, path:, bytes:} records. Used by scripts/build.rb
      # (--format=ttf-per-plane) and scripts/release.rb.
      def write_per_plane_ttfs(out_dir:)
        blueprint = partitioner.call(cp_map.donor_labels)
        stitcher = Fontisan::Stitcher.new
        donors.each_value do |d|
          stitcher.add_source(d.label, d.outline_source, remap: d.remap)
        end
        blueprint.apply_to(stitcher)

        catalog = Essenfont::UcodeRef.catalog
        blueprint.names.map do |name|
          plane_num = name.to_s.sub("plane_", "").to_i
          plane = catalog.find_plane(plane_num)
          face_name = plane&.short_name&.to_s || name.to_s
          path = File.join(out_dir, "Essenfont-#{face_name}.ttf")
          stitcher.write_to(path, format: :ttf, subfont: name)
          { name: face_name, path: path, bytes: File.size(path) }
        end
      end

      # Write a single BMP-only face (legacy TTF or OTF). Returns the
      # output path. Used by scripts/build.rb (--format=ttf / --format=otf).
      def call_single_face(output_path:, format:)
        bmp_map = cp_map.map.select { |cp, _| cp <= 0xFFFF }

        stitcher = Fontisan::Stitcher.new
        donors.each_value do |d|
          stitcher.add_source(d.label, d.outline_source, remap: d.remap)
        end

        first_label = donors.values.first.label
        stitcher.include_notdef(from: first_label, into: :legacy)

        bmp_map.each_slice(1000) do |slice|
          slice.each do |cp, info|
            stitcher.include_codepoints([cp], from: info[:label], into: :legacy)
          end
        end

        stitcher.write_to(output_path, format: format, subfont: :legacy)
        output_path
      end

      private

      def coerce_cp_map(cp_map)
        return cp_map if cp_map.is_a?(Essenfont::CpMap)

        Essenfont::CpMap.new(cp_map)
      end

      def default_partitioner
        Fontisan::Stitcher::PartitionStrategy::ByPlane.new
      end

      def base_info_values
        {
          family_name: family,
          style_name: Naming::SUBFAMILY,
          version_major: Naming.version_major,
          version_minor: Naming.version_minor,
          copyright: Naming::COPYRIGHT
        }
      end
    end
  end
end
