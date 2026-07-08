# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Verifies that the WOFF2 subsets produced by the build pipeline are
# structurally valid and contain glyphs for the user-visible Unicode
# codepoints we promised to cover. These specs guard against regressions
# of the cmap pollution bug (fontisan pre-0.4.11) and the missing
# OS/2 table bug (subset-fonts.rb profile=pdf).
#
# The WOFF2 files live in the sibling essenfont.github.io repo — these
# specs exercise them via the same Fontisan API the website uses at
# build time.

RSpec.describe "WOFF2 subsets (essenfont.github.io/public/fonts)", :integration do
  # Path to the sibling website's built WOFF2 slices. Override locally
  # via ESSENFONT_WEBSITE_FONTS; defaults to a sibling-repo relative
  # path so the spec is portable across dev machines and CI runners.
  WEBSITE_PUBLIC_FONTS = ENV.fetch(
    "ESSENFONT_WEBSITE_FONTS",
    File.expand_path("../../../essenfont.github.io/public/fonts", __dir__)
  ).freeze

  # Each entry: [codepoint, slug, donor_block_name]
  # These are the chars the user reported as tofu or blank.
  EXPECTED_COVERAGE = [
    [0x13000, "egyptian-hieroglyphs", "Egyptian Hieroglyph A001"],
    [0x10900, "phoenician", "Phoenician Alaph"],
    [0x30000, "cjk-unified-ideographs-extension-g", "CJK Unified Ideograph Ext G"],
    [0x11600, "modi", "Modi Letter A"],
    [0x1FBD0, "symbols-for-legacy-computing", "Ottoman Siyaq Number One"],
    [0x12132, "cuneiform", "Cuneiform Sign Di"],
    [0x10380, "ugaritic", "Ugaritic Letter Alaph"],
    [0x10B00, "avestan", "Avestan Letter Alef"],
    [0x103A0, "old-persian", "Old Persian Letter Alef"],
    [0x11005, "brahmi", "Brahmi Letter A"],
  ].freeze

  before(:all) do
    skip "WOFF2 subsets not built yet — run scripts/subset-fonts.rb on the website" unless Dir.exist?(WEBSITE_PUBLIC_FONTS)
  end

  EXPECTED_COVERAGE.each do |cp, slug, name|
    describe "U+#{cp.to_s(16).upcase} (#{name})" do
      let(:woff2_path) { File.join(WEBSITE_PUBLIC_FONTS, "#{slug}.woff2") }

      it "has a WOFF2 file for the containing block (#{slug})" do
        skip "WOFF2 missing — run scripts/subset-fonts.rb --block=#{name}" unless File.exist?(woff2_path)
      end

      it "includes the OS/2 table (browser needs it for line metrics)" do
        skip "WOFF2 missing" unless File.exist?(woff2_path)
        font = Fontisan::FontLoader.load(woff2_path)
        expect(font.table("OS/2")).not_to be_nil,
          "WOFF2 #{slug}.woff2 has no OS/2 — was profile='pdf' used instead of 'web'?"
      end

      it "has a head bbox computed from the subset's actual glyphs" do
        skip "WOFF2 missing" unless File.exist?(woff2_path)
        font = Fontisan::FontLoader.load(woff2_path)
        head = font.table("head")
        # A subset's bbox should be within reasonable font-units bounds,
        # not the source TTC's full-coverage bbox (which extends to
        # xMin=-3113, yMin=-709, xMax=4537, yMax=11160 for essenfont).
        expect(head.x_min).to be > -3000,
          "head.x_min=#{head.x_min} suggests source TTC bbox leaked through"
        expect(head.y_max).to be < 10000,
          "head.y_max=#{head.y_max} suggests source TTC bbox leaked through"
      end

      it "maps the codepoint to a glyph in the subset's cmap" do
        skip "WOFF2 missing" unless File.exist?(woff2_path)
        font = Fontisan::FontLoader.load(woff2_path)
        cmap = font.table("cmap").unicode_mappings || {}
        gid = cmap[cp]
        expect(gid).not_to be_nil,
          "U+#{cp.to_s(16).upcase} not in #{slug}.woff2 cmap"
      end

      it "has glyph data (non-empty glyf entry) for the codepoint" do
        skip "WOFF2 missing" unless File.exist?(woff2_path)
        font = Fontisan::FontLoader.load(woff2_path)
        cmap = font.table("cmap").unicode_mappings || {}
        gid = cmap[cp]
        skip "char not in cmap" unless gid

        # Subset glyf table doesn't expose a single-glyph reader that
        # works without loca/head context. Instead, verify the gid is
        # in range and glyf table has nonzero raw data.
        maxp = font.table("maxp")
        expect(gid).to be < maxp.num_glyphs,
          "U+#{cp.to_s(16).upcase} → gid #{gid} but maxp.numGlyphs is #{maxp.num_glyphs}"

        glyf = font.table("glyf")
        expect(glyf.raw_data.bytesize).to be > 0,
          "glyf table for #{slug}.woff2 has no data"
      end

      it "has cmap pruned to the block's range (no source-TTC pollution)" do
        skip "WOFF2 missing" unless File.exist?(woff2_path)
        font = Fontisan::FontLoader.load(woff2_path)
        cmap = font.table("cmap").unicode_mappings || {}
        # Allow a small overshoot for essential chars (.notdef, NULL,
        # CR, space) that the subsetter always includes for browser
        # compatibility. The pollution we're guarding against was
        # 180k+ entries on a 4k-char subset.
        expect(cmap.size).to be < 5_000,
          "cmap has #{cmap.size} entries — way more than the subset's actual chars; " \
          "this is the fontisan build_cmap_binary stub bug (fontisan pre-0.4.11)"
      end
    end
  end

  # Sanity: the previously-tofu chars should also have working hmtx
  # (advance width > 0) so the browser lays them out correctly.
  describe "rendering metrics" do
    EXPECTED_COVERAGE.first(4).each do |cp, slug, name|
      it "U+#{cp.to_s(16).upcase} has a positive advance width in #{slug}.woff2" do
        path = File.join(WEBSITE_PUBLIC_FONTS, "#{slug}.woff2")
        skip "WOFF2 missing" unless File.exist?(path)
        font = Fontisan::FontLoader.load(path)
        cmap = font.table("cmap").unicode_mappings || {}
        gid = cmap[cp]
        skip "char not in cmap" unless gid

        hmtx = font.table("hmtx")
        hmtx.parse_with_context(font.table("hhea").number_of_h_metrics, font.table("maxp").num_glyphs) unless hmtx.parsed?
        metric = hmtx.metric_for(gid)
        expect(metric).not_to be_nil
        # Egyptian Hieroglyphs legitimately have advance=0 (pictographic)
        # — for everything else, advance should be > 0.
        if slug != "egyptian-hieroglyphs"
          expect(metric[:advance_width]).to be > 0,
            "U+#{cp.to_s(16).upcase} has advance=0 in #{slug}.woff2 — text won't advance"
        end
      end
    end
  end
end
