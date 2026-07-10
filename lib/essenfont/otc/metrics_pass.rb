# frozen_string_literal: true

module Essenfont
  module Otc
    # MetricsPass: recompute each TTC face's vertical metrics from the
    # actual glyph extents after the Stitcher writes the file.
    #
    # Problem: fontisan's Stitcher inherits each face's head/hhea/OS-2
    # tables from one of its donors. The inherited metrics are frozen
    # at that donor's profile — typically a Latin-shaped profile
    # (ascent=800, descent=-200). Faces carrying tall scripts
    # (Tangut, Egyptian Hieroglyphs, Cuneiform) overflow these frozen
    # metrics at render time, causing visible clipping.
    #
    # Constraint: fontisan's table objects (HeadTable, HheaTable,
    # OS2Table) expose attr_reader only — no setters. In-memory
    # mutation after stitch is impossible without a fontisan release.
    #
    # Solution: post-write binary patch. After the Stitcher writes the
    # TTC file, MetricsPass opens the binary, locates each face's
    # head/hhea/OS-2/glyf/loca tables via the sfnt table directory,
    # computes the actual bbox union from glyf, and patches the metric
    # bytes in-place. This is format-level surgery — no fontisan
    # internal API dependency.
    #
    # Design (MECE):
    #   FaceTableLocator   — parses TTC + sfnt headers → face table offsets
    #   GlyphExtentsScanner — walks glyf/loca → bbox union per face
    #   FaceMetricsPatcher  — patches head + hhea + OS/2 byte values
    #
    class MetricsPass
      # Minimum ascent. Latin profile floor; faces with taller glyphs
      # grow past this automatically.
      ASCENT_FLOOR = 800

      # Maximum descent (negative). Latin profile ceiling.
      DESCENT_CEILING = -200

      # Default line gap (rely on ascent/descent alone).
      DEFAULT_LINE_GAP = 0

      # OS/2 usWinAscent/usWinDescent are uint16 — cannot exceed this.
      WIN_METRIC_CAP = 0xFFFF

      # Mac epoch (1904-01-01 UTC) for head.modified field. OTS rejects
      # fonts with zero timestamps; this keeps the value fresh.
      MAC_EPOCH = 2_082_844_800

      attr_reader :ttc_path

      # @param ttc_path [String] path to the TTC file to patch in-place
      def initialize(ttc_path)
        @ttc_path = ttc_path
      end

      # Recompute head.bbox + hhea + OS/2 per face from actual glyphs.
      # Patches the file in-place.
      #
      # @return [true] on success
      def recompute!
        data = File.binread(ttc_path)

        FaceTableLocator.new(data).each_face do |face_offset|
          extents = GlyphExtentsScanner.new(data, face_offset).call
          FaceMetricsPatcher.new(data, face_offset, extents).patch!
        end

        File.binwrite(ttc_path, data)
        true
      end

      # Class-level convenience.
      def self.recompute!(ttc_path)
        new(ttc_path).recompute!
      end
    end

    # Locates each face's sfnt offset within a TTC (or treats a bare
    # TTF as a single-face collection). Yields each face's sfnt base
    # offset to the caller.
    #
    # Internal to MetricsPass. Defined at module level so it can be
    # tested independently if needed, but not autoload-registered
    # (loaded transitively with metrics_pass.rb).
    class FaceTableLocator
      TTC_MAGIC = "ttcf"

      attr_reader :data

      def initialize(data)
        @data = data
      end

      def each_face
        return enum_for(:each_face) unless block_given?

        face_offsets.each { |offset| yield offset }
      end

      private

      def face_offsets
        ttc? ? parse_ttc_offsets : [0]
      end

      def ttc?
        data.byteslice(0, 4) == TTC_MAGIC
      end

      def parse_ttc_offsets
        num_fonts = data.unpack1("x8N")
        Array.new(num_fonts) { |i| data.unpack1("x#{12 + i * 4}N") }
      end
    end


    # Walks a face's glyf/loca tables to compute the actual bbox union
    # of all glyphs. Returns a Extents value object.
    class GlyphExtentsScanner
      attr_reader :data, :face_offset, :tables

      # @param data [String] binary TTC/TTF data
      # @param face_offset [Integer] byte offset to this face's sfnt header
      def initialize(data, face_offset)
        @data = data
        @face_offset = face_offset
        @tables = parse_table_directory
      end

      # @return [Extents] bbox union across all glyphs in this face
      def call
        return Extents.empty if tables["glyf"].nil? || tables["loca"].nil?

        extents = scan_glyf_extents
        extents.empty? ? Extents.zero : extents
      end

      private

      def parse_table_directory
        num_tables = data.unpack1("@#{face_offset + 4}n")
        dir = {}

        num_tables.times do |i|
          rec_offset = face_offset + 12 + i * 16
          tag = data.byteslice(rec_offset, 4)
          offset = data.unpack1("@#{rec_offset + 8}N")
          length = data.unpack1("@#{rec_offset + 12}N")
          dir[tag] = [offset, length]
        end

        dir
      end

      def scan_glyf_extents
        glyf_off, _ = tables["glyf"]
        loca_off, loca_len = tables["loca"]
        head_off, _ = tables["head"]

        index_format = data.unpack1("@#{head_off + 50}n") # 0 = short, 1 = long
        maxp_off, _ = tables["maxp"]
        num_glyphs = data.unpack1("@#{maxp_off + 4}n")

        extents = Extents.empty

        num_glyphs.times do |gid|
          raw_off = glyph_raw_offset(gid, loca_off, index_format)
          next if raw_off == raw_offset_for(gid + 1, loca_off, index_format) # empty glyph

          glyph_start = glyf_off + raw_off
          next if glyph_start + 10 > data.bytesize  # need at least 10 bytes for bbox

          # Glyph header: int16 numberOfContours, then 4 × int16 bbox
          x_min, y_min, x_max, y_max = data.unpack("@#{glyph_start + 2}s4")
          next if x_min.nil?
          extents.absorb!(x_min, y_min, x_max, y_max)
        end

        extents
      end

      def glyph_raw_offset(gid, loca_off, index_format)
        raw_offset_for(gid, loca_off, index_format)
      end

      def raw_offset_for(gid, loca_off, index_format)
        if index_format.zero?
          # short loca: uint16 offsets, value × 2
          data.unpack1("@#{loca_off + gid * 2}n") * 2
        else
          # long loca: uint32 offsets
          data.unpack1("@#{loca_off + gid * 4}N")
        end
      end
    end


    # Patches head.bbox + hhea + OS/2 fields in-place on the binary
    # data string for one face.
    class FaceMetricsPatcher
      attr_reader :data, :face_offset, :extents, :tables

      # @param data [String] binary TTC/TTF data (mutated in-place)
      # @param face_offset [Integer] byte offset to this face's sfnt header
      # @param extents [Extents] computed glyph extents
      def initialize(data, face_offset, extents)
        @data = data
        @face_offset = face_offset
        @extents = extents
        @tables = parse_table_directory
      end

      def patch!
        patch_head!
        patch_hhea!
        patch_os2!
      end

      private

      def parse_table_directory
        num_tables = data.unpack1("@#{face_offset + 4}n")
        dir = {}

        num_tables.times do |i|
          rec_offset = face_offset + 12 + i * 16
          tag = data.byteslice(rec_offset, 4)
          offset = data.unpack1("@#{rec_offset + 8}N")
          length = data.unpack1("@#{rec_offset + 12}N")
          dir[tag] = [offset, length]
        end

        dir
      end

      def patch_head!
        return unless tables["head"]

        off, _ = tables["head"]
        # head.xMin/yMin/xMax/yMax at offsets 36, 38, 40, 42 (int16 each)
        data[off + 36, 8] = [
          safe_metric(extents.x_min), safe_metric(extents.y_min),
          safe_metric(extents.x_max), safe_metric(extents.y_max)
        ].pack("s4")

        # head.modified at offset 28 (LONGDATETIME = int64, seconds since 1904)
        now = Time.now.utc.to_i + MetricsPass::MAC_EPOCH
        data[off + 28, 8] = [now].pack("q>")
      end

      def patch_hhea!
        return unless tables["hhea"]

        off, _ = tables["hhea"]
        ascent = [safe_metric(extents.y_max), MetricsPass::ASCENT_FLOOR].max
        descent = [safe_metric(extents.y_min), MetricsPass::DESCENT_CEILING].min

        # hhea.ascent/descent/lineGap at offsets 4, 6, 8 (int16 each)
        data[off + 4, 6] = [ascent, descent, MetricsPass::DEFAULT_LINE_GAP].pack("s3")
      end

      def patch_os2!
        return unless tables["OS/2"]

        off, _ = tables["OS/2"]
        ascent = [safe_metric(extents.y_max), MetricsPass::ASCENT_FLOOR].max
        descent = [safe_metric(extents.y_min), MetricsPass::DESCENT_CEILING].min

        # OS/2.sTypoAscender/Descender/LineGap at 68, 70, 72 (int16)
        data[off + 68, 6] = [ascent, descent, MetricsPass::DEFAULT_LINE_GAP].pack("s3")

        # OS/2.usWinAscent/usWinDescent at 74, 76 (uint16)
        data[off + 74, 4] = [
          [ascent, MetricsPass::WIN_METRIC_CAP].min,
          [descent.abs, MetricsPass::WIN_METRIC_CAP].min
        ].pack("S2")
      end

      private

      def safe_metric(value)
        return 0 if value.is_a?(Float) && (value.infinite? || value.nan?)
        value.to_i
      end
    end
    # During scanning, absorb! grows the bbox per glyph. After scanning
    # completes, the caller reads the final values via attr_reader.
    class Extents
      attr_reader :x_min, :y_min, :x_max, :y_max

      def initialize(x_min:, y_min:, x_max:, y_max:)
        @x_min = x_min
        @y_min = y_min
        @x_max = x_max
        @y_max = y_max
      end

      def self.empty
        new(x_min: Float::INFINITY, y_min: Float::INFINITY,
            x_max: -Float::INFINITY, y_max: -Float::INFINITY)
      end

      def self.zero
        new(x_min: 0, y_min: 0, x_max: 0, y_max: 0)
      end

      def empty?
        x_min == Float::INFINITY
      end

      # Expand the bbox to include the given extents. Returns self for
      # chaining during accumulation (mutates internal state — this is
      # a builder pattern, not a functional update).
      def absorb!(x_min, y_min, x_max, y_max)
        return self if x_min.nil? || y_min.nil?

        @x_min = x_min if @x_min > x_min
        @y_min = y_min if @y_min > y_min
        @x_max = x_max if @x_max < x_max
        @y_max = y_max if @y_max < y_max
        self
      end
    end

  end
end
