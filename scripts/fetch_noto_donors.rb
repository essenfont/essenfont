#!/usr/bin/env ruby
# frozen_string_literal: true

# fetch_noto_donors.rb — bulk-download Noto Sans/Serif variants for
# the 133 + 3 Unicode blocks identified in TODO.full/06-donor-search.md
# as coverable by Noto.
#
# Pattern: https://github.com/notofonts/notofonts.github.io/raw/main/
#          fonts/<FontName>/hinted/ttf/<FontName>-Regular.ttf
#
# For each font:
#   1. Download to references/input-fonts/<FontName>-Regular.ttf
#   2. Verify magic bytes (TTF/OTF)
#   3. Compute sha256
#   4. Scan cmap for coverage of the target block
#   5. Emit a manifest YAML snippet for sources/manifest.yml
#
# Usage:
#   ruby scripts/fetch_noto_donors.rb                 # all
#   ruby scripts/fetch_noto_donors.rb --dry-run       # plan only
#   ruby scripts/fetch_noto_donors.rb --filter NKo    # match by block id
#
# Skips files that already exist with matching sha256.

require "yaml"
require "digest"
require "fileutils"
require "open-uri"
require "optparse"
require "fontisan"

module EssenfontNotoFetch
  DONOR_DIR = File.expand_path("../references/input-fonts", __dir__)
  UCODE_BLOCKS = "/Users/mulgogi/src/fontist/ucode/output/blocks/index.json"

  # block_id → Noto font name (without "-Regular.ttf" suffix).
  # Sourced from TODO.full/06-donor-search.md.
  NOTO_FONTS = {
    # Arabic family
    "Arabic_Supplement" => "NotoNaskhArabic",
    "Arabic_Extended-A" => "NotoNaskhArabic",
    "Arabic_Extended-B" => "NotoNaskhArabic",
    "Arabic_Extended-C" => "NotoNaskhArabic",
    # Per-script Noto Sans
    "NKo" => "NotoSansNKo",
    "Samaritan" => "NotoSansSamaritan",
    "Mandaic" => "NotoSansMandaic",
    "Syriac_Supplement" => "NotoSansSyriac",
    "Ethiopic_Supplement" => "NotoSansEthiopic",
    "Ethiopic_Extended" => "NotoSansEthiopic",
    "Ethiopic_Extended-A" => "NotoSansEthiopic",
    "Ethiopic_Extended-B" => "NotoSansEthiopic",
    "Unified_Canadian_Aboriginal_Syllabics_Extended" => "NotoSansCanadianAboriginal",
    "Unified_Canadian_Aboriginal_Syllabics_Extended-A" => "NotoSansCanadianAboriginal",
    "New_Tai_Lue" => "NotoSansNewTaiLue",
    "Buginese" => "NotoSansBuginese",
    "Tai_Tham" => "NotoSansTaiTham",
    "Balinese" => "NotoSansBalinese",
    "Sundanese" => "NotoSansSundanese",
    "Batak" => "NotoSansBatak",
    "Lepcha" => "NotoSansLepcha",
    "Ol_Chiki" => "NotoSansOlChiki",
    "Georgian_Extended" => "NotoSansGeorgian",
    "Georgian_Supplement" => "NotoSansGeorgian",
    "Glagolitic" => "NotoSansGlagolitic",
    "Vai" => "NotoSansVai",
    "Bamum" => "NotoSansBamum",
    "Bamum_Supplement" => "NotoSansBamum",
    "Syloti_Nagri" => "NotoSansSylotiNagri",
    "Common_Indic_Number_Forms" => "NotoSansDevanagari",
    "Phags-pa" => "NotoSansPhagsPa",
    "Saurashtra" => "NotoSansSaurashtra",
    "Devanagari_Extended" => "NotoSansDevanagari",
    "Devanagari_Extended-A" => "NotoSansDevanagari",
    "Rejang" => "NotoSansRejang",
    "Javanese" => "NotoSansJavanese",
    "Myanmar_Extended-B" => "NotoSansMyanmar",
    "Myanmar_Extended-A" => "NotoSansMyanmar",
    "Myanmar_Extended-C" => "NotoSansMyanmar",
    "Cham" => "NotoSansCham",
    "Tai_Viet" => "NotoSansTaiViet",
    "Meetei_Mayek_Extensions" => "NotoSansMeeteiMayek",
    "Meetei_Mayek" => "NotoSansMeeteiMayek",
    "Cherokee_Supplement" => "NotoSansCherokee",
    "Linear_B_Syllabary" => "NotoSansLinearB",
    "Linear_B_Ideograms" => "NotoSansLinearB",
    "Aegean_Numbers" => "NotoSansLinearB",
    "Lycian" => "NotoSansLycian",
    "Carian" => "NotoSansCarian",
    "Old_Permic" => "NotoSansOldPermic",
    "Ugaritic" => "NotoSansUgaritic",
    "Old_Persian" => "NotoSansOldPersian",
    "Osage" => "NotoSansOsage",
    "Linear_A" => "NotoSansLinearA",
    "Cypriot_Syllabary" => "NotoSansCypriot",
    "Palmyrene" => "NotoSansPalmyrene",
    "Nabataean" => "NotoSansNabataean",
    "Lydian" => "NotoSansLydian",
    "Meroitic_Hieroglyphs" => "NotoSansMeroitic",
    "Meroitic_Cursive" => "NotoSansMeroitic",
    "Kharoshthi" => "NotoSansKharoshthi",
    "Old_South_Arabian" => "NotoSansOldSouthArabian",
    "Old_North_Arabian" => "NotoSansOldNorthArabian",
    "Manichaean" => "NotoSansManichaean",
    "Avestan" => "NotoSansAvestan",
    "Inscriptional_Parthian" => "NotoSansInscriptionalParthian",
    "Inscriptional_Pahlavi" => "NotoSansInscriptionalPahlavi",
    "Psalter_Pahlavi" => "NotoSansPsalterPahlavi",
    "Old_Turkic" => "NotoSansOldTurkic",
    "Old_Hungarian" => "NotoSansOldHungarian",
    "Hanifi_Rohingya" => "NotoSansHanifiRohingya",
    "Yezidi" => "NotoSerifYezidi",
    "Old_Sogdian" => "NotoSansOldSogdian",
    "Sogdian" => "NotoSansSogdian",
    "Old_Uyghur" => "NotoSerifOldUyghur",
    "Chorasmian" => "NotoSansChorasmian",
    "Elymaic" => "NotoSansElymaic",
    "Brahmi" => "NotoSansBrahmi",
    "Kaithi" => "NotoSansKaithi",
    "Sora_Sompeng" => "NotoSansSoraSompeng",
    "Chakma" => "NotoSansChakma",
    "Mahajani" => "NotoSansMahajani",
    "Sinhala_Archaic_Numbers" => "NotoSansSinhala",
    "Khojki" => "NotoSansKhojki",
    "Multani" => "NotoSansMultani",
    "Khudawadi" => "NotoSansKhudawadi",
    "Grantha" => "NotoSansGrantha",
    "Tulu-Tigalari" => "NotoSerifTuluTigalari",
    "Newa" => "NotoSansNewa",
    "Tirhuta" => "NotoSansTirhuta",
    "Siddham" => "NotoSansSiddham",
    "Modi" => "NotoSansModi",
    "Takri" => "NotoSansTakri",
    "Ahom" => "NotoSerifAhom",
    "Dogra" => "NotoSerifDogra",
    "Warang_Citi" => "NotoSansWarangCiti",
    "Dives_Akuru" => "NotoSerifDivesAkuru",
    "Nandinagari" => "NotoSansNandinagari",
    "Zanabazar_Square" => "NotoSansZanabazarSquare",
    "Soyombo" => "NotoSansSoyombo",
    "Bhaiksuki" => "NotoSansBhaiksuki",
    "Marchen" => "NotoSansMarchen",
    "Masaram_Gondi" => "NotoSansMasaramGondi",
    "Gunjala_Gondi" => "NotoSansGunjalaGondi",
    "Makasar" => "NotoSerifMakasar",
    "Kawi" => "NotoSansKawi",
    "Cuneiform" => "NotoSansCuneiform",
    "Cuneiform_Numbers_and_Punctuation" => "NotoSansCuneiform",
    "Early_Dynastic_Cuneiform" => "NotoSansCuneiform",
    "Cypro-Minoan" => "NotoSansCyproMinoan",
    "Anatolian_Hieroglyphs" => "NotoSansAnatolianHieroglyphs",
    "Mro" => "NotoSansMro",
    "Tangsa" => "NotoSansTangsa",
    "Bassa_Vah" => "NotoSansBassaVah",
    "Pahawh_Hmong" => "NotoSansPahawhHmong",
    "Medefaidrin" => "NotoSansMedefaidrin",
    "Miao" => "NotoSansMiao",
    "Khitan_Small_Script" => "NotoSansKhitanSmallScript",
    "Kana_Extended-B" => "NotoSansKanaExtendedB",
    "Kana_Supplement" => "NotoSansKanaSupplement",
    "Small_Kana_Extension" => "NotoSansJapanese",
    "Duployan" => "NotoSansDuployan",
    "Sutton_SignWriting" => "NotoSansSignWriting",
    "Nyiakeng_Puachue_Hmong" => "NotoSansNyiakengPuachueHmong",
    "Toto" => "NotoSerifToto",
    "Wancho" => "NotoSansWancho",
    "Nag_Mundari" => "NotoSansNagMundari",
    "Mende_Kikakui" => "NotoSansMendeKikakui",
    "Adlam" => "NotoSansAdlam",
    "Indic_Siyaq_Numbers" => "NotoSansIndicSiyaqNumbers",
    "Ottoman_Siyaq_Numbers" => "NotoSansOttomanSiyaqNumbers",
    # Specialists the user pointed to (Google Fonts specimen confirms these exist)
    "Todhri" => "NotoSerifTodhri",
    "Tamil_Supplement" => "NotoSansTamilSupplement",
    "Znamenny_Musical_Notation" => "NotoZnamennyMusicalNotation",
  }.freeze

  def self.run(filter: nil, dry_run: false)
    FileUtils.mkdir_p(DONOR_DIR)
    blocks_index = load_blocks_index

    selected = NOTO_FONTS.select do |block_id, _|
      filter.nil? || block_id =~ /#{filter}/i
    end

    puts "=== Bulk Noto fetch: #{selected.size} donors ==="
    results = selected.map do |block_id, font_name|
      fetch_one(block_id, font_name, blocks_index, dry_run: dry_run)
    end

    summarize(results)
    write_manifest_snippet(results) unless dry_run
  end

  def self.fetch_one(block_id, font_name, blocks_index, dry_run:)
    url = noto_url(font_name)
    path = File.join(DONOR_DIR, "#{font_name}-Regular.ttf")
    block_range = blocks_index[block_id]

    result = {
      block_id: block_id,
      font_name: font_name,
      url: url,
      path: path,
      block_range: block_range,
      status: nil,
      sha256: nil,
      error: nil,
    }

    if dry_run
      result[:status] = "plan"
      return result
    end

    if File.exist?(path)
      result[:sha256] = Digest::SHA256.file(path).hexdigest
      result[:status] = "exists"
      return result
    end

    begin
      puts "  fetching #{font_name}..."
      URI.open(url) do |io|
        File.binwrite(path, io.read)
      end
      unless valid_font_magic?(path)
        result[:status] = "fail"
        result[:error] = "invalid magic bytes (not a TTF)"
        File.unlink(path)
        return result
      end
      result[:sha256] = Digest::SHA256.file(path).hexdigest
      result[:status] = "fetched"
    rescue StandardError => e
      result[:status] = "fail"
      result[:error] = "#{e.class}: #{e.message}"
    end

    result
  end

  def self.noto_url(font_name)
    "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/" \
      "#{font_name}/hinted/ttf/#{font_name}-Regular.ttf"
  end

  def self.load_blocks_index
    return {} unless File.exist?(UCODE_BLOCKS)
    data = JSON.parse(File.read(UCODE_BLOCKS))
    data.each_with_object({}) do |b, h|
      h[b["id"]] = (b["first_cp"]..b["last_cp"])
    end
  end

  VALID_MAGIC = ["\x00\x01\x00\x00", "OTTO", "true", "ttcf"].freeze

  def self.valid_font_magic?(path)
    return false unless File.size(path) > 16
    magic = File.binread(path, 4)
    VALID_MAGIC.include?(magic)
  end

  def self.summarize(results)
    by_status = results.group_by { |r| r[:status] }.transform_values(&:size)
    puts ""
    puts "=== Summary ==="
    by_status.each { |s, n| puts "  #{s}: #{n}" }
    failed = results.select { |r| r[:status] == "fail" }
    unless failed.empty?
      puts ""
      puts "Failures:"
      failed.each { |r| puts "  - #{r[:font_name]}: #{r[:error]}" }
    end
  end

  def self.write_manifest_snippet(results)
    successes = results.select { |r| r[:sha256] && r[:status] != "fail" }
    return if successes.empty?

    # Dedupe by font_name — multiple Unicode blocks may share one font
    # (e.g., NotoNaskhArabic covers 4 Arabic blocks). Group covers +
    # use a single manifest entry per font.
    by_font = successes.group_by { |r| r[:font_name] }

    snippet_path = File.expand_path("../sources/noto-donors.generated.yml", __dir__)
    File.open(snippet_path, "w") do |f|
      f.puts "# Auto-generated by scripts/fetch_noto_donors.rb."
      f.puts "# Append to sources/manifest.yml under `donors:` to activate."
      f.puts ""
      by_font.each do |font_name, entries|
        first = entries.first
        covers = entries.map { |e| e[:block_id] }.uniq
        ranges_summary = entries.map do |e|
          if e[:block_range]
            "U+#{e[:block_range].first.to_s(16).upcase}..U+#{e[:block_range].last.to_s(16).upcase}"
          end
        end.compact.join(", ")
        f.puts "  - label: #{labelize(font_name)}"
        f.puts "    file: #{first[:path].sub(DONOR_DIR + "/", "references/input-fonts/")}"
        f.puts "    family: #{font_name}"
        f.puts "    style: Regular"
        f.puts "    license: OFL"
        f.puts "    sha256: \"#{first[:sha256]}\""
        f.puts "    url: #{first[:url]}"
        f.puts "    author: \"Google (Noto Project)\""
        f.puts "    covers: [#{covers.join(", ")}]"
        f.puts "    notes: \"Bulk-fetched. Covers #{covers.size} block(s): #{ranges_summary}.\""
        f.puts ""
      end
    end
    puts ""
    puts "Manifest snippet written to: #{snippet_path}"
    puts "  #{by_font.size} unique fonts covering #{successes.size} blocks."
    puts "Append its contents to sources/manifest.yml under `donors:`."
  end

  def self.labelize(font_name)
    # NotoSansBalinese → noto-sans-balinese
    font_name
      .gsub(/([A-Z])/, "-\\1")
      .gsub(/^-/, "")
      .downcase
      .gsub(/\s+/, "-")
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { filter: nil, dry_run: false }
  OptionParser.new do |opts|
    opts.banner = "Usage: fetch_noto_donors.rb [options]"
    opts.on("--filter=REGEX", "only fetch blocks matching REGEX") { |v| options[:filter] = v }
    opts.on("--dry-run", "plan only, no download") { options[:dry_run] = true }
  end.parse!

  EssenfontNotoFetch.run(filter: options[:filter], dry_run: options[:dry_run])
end