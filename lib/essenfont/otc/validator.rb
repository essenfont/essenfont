# frozen_string_literal: true

module Essenfont
  module Otc
    # Validator: post-build font well-formedness checks.
    #
    # Combines the checks previously split between scripts/verify.rb
    # (single-font checks: magic, checksum, maxp, cmap, name, upm) and
    # scripts/build.rb#validate_collection! (collection checks: face
    # count, glyph cap, cmap union). Both scripts now delegate here.
    #
    # Interface:
    #   .check(path, expected_faces: nil, expected_cmap_union_size: nil)
    #     → Array of Failure records (empty = all pass)
    #   .check!(path, **opts)
    #     → raises CollectionValidation on first failure
    #
    class Validator
      Failure = Struct.new(:description, :detail, keyword_init: true) do
        def message
          detail ? "#{description} (#{detail})" : description
        end
      end

      GLYPH_CAP = 65_535

      module_function

      def check(path, expected_faces: nil, expected_cmap_union_size: nil)
        failures = []
        return [Failure.new(description: "file not found: #{path}")] unless File.exist?(path)

        font_checks(path, failures)

        if expected_faces
          collection_checks(path, expected_faces, expected_cmap_union_size, failures)
        end

        failures
      end

      def check!(path, **opts)
        failures = check(path, **opts)
        return if failures.empty?

        raise Essenfont::Otc::Errors::CollectionValidation,
              failures.map { |f| "  - #{f.message}" }.join("\n")
      end

      # -- Single-font well-formedness (from verify.rb) --------------------

      def font_checks(path, failures)
        font = Fontisan::FontLoader.load(path)
        return unless font

        check_head(font, failures)
        check_maxp(font, failures)
        check_cmap(font, failures)
        check_name(font, failures)
      rescue StandardError => e
        failures << Failure.new(description: "font load failed", detail: e.message)
      end

      def check_head(font, failures)
        head = font.table("head")
        unless head
          failures << Failure.new(description: "head table missing")
          return
        end
        failures << Failure.new(description: "head magic number") unless head.magic_number == 0x5F0F3CF5
        failures << Failure.new(description: "head checksum adjusted (non-zero)") unless head.checksum_adjustment&.nonzero?
        failures << Failure.new(description: "head units_per_em = 1000") unless head.units_per_em == 1000
      end

      def check_maxp(font, failures)
        maxp = font.table("maxp")
        return failures << Failure.new(description: "maxp table missing") unless maxp

        failures << Failure.new(description: "maxp num_glyphs > 0") unless maxp.num_glyphs&.positive?
      end

      def check_cmap(font, failures)
        return failures << Failure.new(description: "cmap table present") unless font.has_table?("cmap")

        cmap = font.table("cmap")
        mappings = cmap&.unicode_mappings
        failures << Failure.new(description: "cmap has unicode mappings") if mappings.nil? || mappings.empty?
      end

      def check_name(font, failures)
        failures << Failure.new(description: "name table present") unless font.has_table?("name")
      end

      # -- Collection-level checks (from build.rb) -------------------------

      def collection_checks(path, expected_faces, expected_cmap_union_size, failures)
        reader = Fontisan::Collection::Reader.open(path)

        unless reader.face_count == expected_faces
          failures << Failure.new(
            description: "face count",
            detail: "#{reader.face_count} faces, expected #{expected_faces}"
          )
        end

        reader.stats.each do |s|
          next if s.glyph_count <= GLYPH_CAP

          failures << Failure.new(
            description: "glyph cap",
            detail: "face #{s.index} has #{s.glyph_count} glyphs (cap #{GLYPH_CAP})"
          )
        end

        return unless expected_cmap_union_size

        union_size = reader.cmap_union.size
        return unless union_size < expected_cmap_union_size * 0.99

        dropped = expected_cmap_union_size - union_size
        failures << Failure.new(
          description: "cmap union",
          detail: "#{dropped} entries dropped (#{union_size} / #{expected_cmap_union_size})"
        )
      end
    end
  end
end
