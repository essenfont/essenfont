# frozen_string_literal: true

module Essenfont
  module Otc
    class Build
      Result = Struct.new(:output_path, :bytes, :subfonts, :subfont_count,
                          keyword_init: true)

      DEFAULT_SUBFONT_FORMAT = :ttf
      DEFAULT_FAMILY = Naming::FAMILY
      DEFAULT_VERSION = Naming::VERSION

      attr_reader :cp_map, :donors, :subfont_format, :partitioner, :family,
                  :version

      def initialize(cp_map:, donors:, subfont_format: DEFAULT_SUBFONT_FORMAT,
                     partitioner: default_partitioner,
                     family: DEFAULT_FAMILY, version: DEFAULT_VERSION)
        unless cp_map.is_a?(Hash)
          raise ArgumentError, "cp_map must be a Hash, got #{cp_map.class}"
        end
        unless donors.is_a?(Hash)
          raise ArgumentError, "donors must be a Hash, got #{donors.class}"
        end

        @cp_map = cp_map
        @donors = donors
        @subfont_format = subfont_format
        @partitioner = partitioner
        @family = family
        @version = version
      end

      def call(output_path:)
        # Essenfont's cp_map is {cp => {label:, gid:}} (preserves the donor
        # gid for the Stitcher). fontisan's PartitionStrategy expects
        # {cp => donor_label} — collapse to the donor label here.
        donor_labels = cp_map.transform_values { |info| info[:label] }

        blueprint = partitioner.call(donor_labels)
        stitcher = Fontisan::Stitcher.new
        donors.each_value { |d| stitcher.add_source(d[:label], d[:font]) }
        stitcher.set_info(base_info_values)

        blueprint.apply_to(stitcher)

        collection = stitcher.write_collection(output_path, format: subfont_format)

        Result.new(
          output_path: collection.path,
          bytes: collection.bytes,
          subfonts: collection.subfonts.map(&:to_h),
          subfont_count: collection.face_count
        )
      end

      private

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
