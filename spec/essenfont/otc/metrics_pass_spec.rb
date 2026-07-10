# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Essenfont::Otc::MetricsPass do
  let(:tmpdir) { Dir.mktmpdir("metrics-pass-spec") }
  let(:ttc_path) { File.join(tmpdir, "test.ttc") }

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  describe ".recompute!" do
    it "patches head.bbox from actual glyph extents" do
      write_minimal_ttc(ttc_path, glyphs: [
        { xMin: -100, yMin: -50, xMax: 500, yMax: 800 },
        { xMin: 0, yMin: 0, xMax: 600, yMax: 900 },
      ])

      described_class.recompute!(ttc_path)

      head = read_head_table(ttc_path)
      expect(head[:xMin]).to eq(-100)
      expect(head[:yMin]).to eq(-50)
      expect(head[:xMax]).to eq(600)
      expect(head[:yMax]).to eq(900)
    end

    it "patches hhea.ascent to at least ASCENT_FLOOR" do
      write_minimal_ttc(ttc_path, glyphs: [{ xMin: 0, yMin: 0, xMax: 100, yMax: 700 }])

      described_class.recompute!(ttc_path)

      hhea = read_hhea_table(ttc_path)
      expect(hhea[:ascent]).to be >= described_class::ASCENT_FLOOR
    end

    it "patches hhea.ascent past floor when glyphs are taller" do
      write_minimal_ttc(ttc_path, glyphs: [{ xMin: 0, yMin: 0, xMax: 100, yMax: 1200 }])

      described_class.recompute!(ttc_path)

      hhea = read_hhea_table(ttc_path)
      expect(hhea[:ascent]).to eq(1200)
    end

    it "patches OS/2.usWinAscent to match hhea.ascent" do
      write_minimal_ttc(ttc_path, glyphs: [{ xMin: 0, yMin: -100, xMax: 100, yMax: 950 }])

      described_class.recompute!(ttc_path)

      os2 = read_os2_table(ttc_path)
      expect(os2[:usWinAscent]).to eq(950)
    end

    it "updates head.modified timestamp" do
      write_minimal_ttc(ttc_path, glyphs: [{ xMin: 0, yMin: 0, xMax: 100, yMax: 800 }])

      described_class.recompute!(ttc_path)

      head = read_head_table(ttc_path)
      expect(head[:modified]).to be > 0
    end
  end

  # -- Helpers: build minimal TTC fixtures --------------------------------

  def write_minimal_ttc(path, glyphs:)
    builder = MinimalTtcBuilder.new(path, glyphs)
    builder.write
  end

  def read_head_table(path)
    data = File.binread(path)
    # Single-face TTF: sfnt starts at offset 0
    num_tables = data.unpack1("@4n")
    head_off = nil
    num_tables.times do |i|
      rec = data.byteslice(12 + i * 16, 16)
      tag = rec.byteslice(0, 4)
      if tag == "head"
        head_off = rec.unpack1("@8N")
        break
      end
    end

    x_min, y_min, x_max, y_max = data.unpack("@#{head_off + 36}s4")
    modified_high, modified_low = data.unpack("@#{head_off + 28}NN")
    {
      xMin: x_min, yMin: y_min, xMax: x_max, yMax: y_max,
      modified: (modified_high << 32) | modified_low
    }
  end

  def read_hhea_table(path)
    data = File.binread(path)
    num_tables = data.unpack1("@4n")
    hhea_off = nil
    num_tables.times do |i|
      rec = data.byteslice(12 + i * 16, 16)
      tag = rec.byteslice(0, 4)
      if tag == "hhea"
        hhea_off = rec.unpack1("@8N")
        break
      end
    end

    asc, desc, gap = data.unpack("@#{hhea_off + 4}s3")
    { ascent: asc, descent: desc, lineGap: gap }
  end

  def read_os2_table(path)
    data = File.binread(path)
    num_tables = data.unpack1("@4n")
    os2_off = nil
    num_tables.times do |i|
      rec = data.byteslice(12 + i * 16, 16)
      tag = rec.byteslice(0, 4)
      if tag == "OS/2"
        os2_off = rec.unpack1("@8N")
        break
      end
    end

    s_typo_asc, s_typo_desc, s_typo_gap = data.unpack("@#{os2_off + 68}s3")
    win_asc, win_desc = data.unpack("@#{os2_off + 74}S2")
    {
      sTypoAscender: s_typo_asc, sTypoDescender: s_typo_desc, sTypoLineGap: s_typo_gap,
      usWinAscent: win_asc, usWinDescent: win_desc
    }
  end

  # Builds a minimal single-face TTF with the given glyphs' bboxes.
  class MinimalTtcBuilder
    attr_reader :path, :glyphs

    def initialize(path, glyphs)
      @path = path
      @glyphs = glyphs
    end

    def write
      # This is a simplified fixture builder for testing MetricsPass.
      # In production, the Stitcher writes real TTCs. Here we build
      # just enough binary structure for MetricsPass to find and patch.
      head = build_head
      glyf, loca = build_glyf_and_loca
      maxp = build_maxp(glyphs.length + 1) # +1 for .notdef
      hhea = build_hhea
      os2 = build_os2

      tables = { "head" => head, "glyf" => glyf, "loca" => loca,
                 "maxp" => maxp, "hhea" => hhea, "OS/2" => os2,
                 "cmap" => build_cmap, "hmtx" => build_hmtx(glyphs.length + 1),
                 "name" => build_name, "post" => build_post }

      write_sfnt(path, tables)
    end

    private

    def build_head
      [0, 1, 0, 0, 0x5F0F3CF5, 0x00010000, 0x000B, 1000,
       0, 0, 0, 0, 0, 0, 0x7FFFFFFF, 0x7FFFFFFF, 0, 0, 0, 0,
       0x8000, 8, 2, 0].pack("s4NNnnq>q>s4nnnq>")
    end

    def build_glyf_and_loca
      glyf = String.new
      offsets = [0]

      # .notdef (empty)
      offsets << glyf.length

      glyphs.each do |g|
        glyf << [0, g[:xMin], g[:yMin], g[:xMax], g[:yMax]].pack("ss4")
        offsets << glyf.length
      end

      # short loca format
      loca = offsets.map { |o| (o / 2) }.pack("n*")
      [glyf, loca]
    end

    def build_maxp(num_glyphs)
      [0x00005000, num_glyphs].pack("Nn") + "\x00".b * 28
    end

    def build_hhea
      [0, 1, 0, 800, -200, 0, 1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].pack("n3s3n11")
    end

    def build_os2
      [4].pack("n") + "\x00".b * 66 + [800, -200, 0, 1000, 200].pack("s3S2") + "\x00".b * 20
    end

    def build_cmap
      [0, 1, 0, 0, 6, 0, 0, 0, 0].pack("nnnnnnn") + "\x00".b * 4
    end

    def build_hmtx(num_glyphs)
      "\x00".b * (num_glyphs * 4)
    end

    def build_name
      [0, 0].pack("nn")
    end

    def build_post
      [0x00030000].pack("N") + "\x00".b * 28
    end

    def write_sfnt(path, tables)
      num_tables = tables.length
      sfnt = String.new
      sfnt << [0x00010000, num_tables, 0x5F0F3CF5].pack("Nnn")

      # Search range calculation
      entry_selector = Math.log2(num_tables).floor
      search_range = (2 ** entry_selector) * 16
      range_shift = num_tables * 16 - search_range
      sfnt << [search_range, entry_selector, range_shift].pack("nnn")

      # Table directory (placeholder offsets)
      dir_offset = 12 + num_tables * 16
      sorted_tags = tables.keys.sort
      current_offset = dir_offset
      offsets = {}

      sorted_tags.each do |tag|
        tag_bytes = tag.ljust(4, " ").byteslice(0, 4)
        sfnt << [0, 0, current_offset, tables[tag].length].pack("a4NN")
        offsets[tag] = current_offset
        padded = tables[tag].length + (4 - tables[tag].length % 4) % 4
        current_offset += padded
      end

      # Table data
      sorted_tags.each do |tag|
        data = tables[tag]
        sfnt << data
        padding = (4 - data.length % 4) % 4
        sfnt << "\x00".b * padding
      end

      File.binwrite(path, sfnt)
    end
  end
end
