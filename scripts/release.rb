#!/usr/bin/env ruby
# frozen_string_literal: true

# Single entry point for the release pipeline. All work happens in one
# Ruby process — no subprocess calls, no `system("bundle exec ...")`.
#
# Usage:
#   ruby scripts/release.rb                  # full release pipeline
#   ruby scripts/release.rb --dry-run        # build but skip publish + upload
#   ruby scripts/release.rb --skip-build     # only emit manifests + pack
#   ruby scripts/release.rb publish --token  # npm publish only (requires npm CLI)

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

$stdout.sync = true
$stderr.sync = true

require "optparse"
require "fileutils"
require "digest"
require "zip"
require "json"
require "zlib"
require "stringio"
require "essenfont"
require "fontisan"

module ReleasePipeline
  PLANES = %i[BMP SMP SIP TIP SSP].freeze
  ROOT = File.expand_path("..", __dir__)

  module_function

  def run(argv)
    options = parse_options(argv)
    setup_output_dir(options[:out_dir])

    puts "=== Essenfont release pipeline v#{Essenfont::Otc::Version::STRING} ==="

    build_fonts(out_dir: options[:out_dir], skip: options[:skip_build])
    encode_woffs(out_dir: options[:out_dir])
    emit_coverage_manifest(out_dir: options[:out_dir])
    emit_provenance(out_dir: options[:out_dir])
    emit_license_pack(out_dir: options[:out_dir])
    emit_svg_exports(out_dir: options[:out_dir])
    build_npm_package(out_dir: options[:out_dir])
    emit_sri_hashes(out_dir: options[:out_dir])
    write_release_manifest(out_dir: options[:out_dir])

    puts "=== Done. Artifacts in #{options[:out_dir]}/ ==="
    list_artifacts(options[:out_dir])
  end

  # ── Build: OTC + per-plane TTFs (both in-process) ──

  def build_fonts(out_dir:, skip:)
    return if skip

    ENV["ESSENFONT_DUMP_CP_MAP"] = "1"

    puts "→ loading manifest + donors"
    manifest = Essenfont::Manifest.load
    donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
    raise "no donors loaded" if donors.empty?

    validate_coverage_gates(manifest:, donors:)

    cp_map = Essenfont::CpMap.from_donors(donors)
                              .filter_reserved
                              .backfill_cc_cf(donors.values.first[:label])
    puts "  cp_map: #{cp_map.size} codepoints"

    dump_cp_map(out_dir:, cp_map:)

    puts "→ building OTC (glyf → TTC)"
    result = Essenfont::Otc::Build.new(
      cp_map: cp_map, donors: donors, subfont_format: :ttf
    ).call(output_path: File.join(out_dir, "Essenfont-Regular.ttc"))
    puts "  TTC: #{result.bytes} bytes, #{result.subfont_count} faces"

    puts "→ building per-plane TTFs"
    partitioner = Fontisan::Stitcher::PartitionStrategy::ByPlane.new
    blueprint = partitioner.call(cp_map.donor_labels)
    stitcher = Fontisan::Stitcher.new
    donors.each_value { |d| stitcher.add_source(d[:label], d[:font], remap: d[:remap]) }
    blueprint.apply_to(stitcher)

    catalog = Essenfont::UcodeRef.catalog
    blueprint.names.each do |name|
      plane_num = name.to_s.sub("plane_", "").to_i
      plane = catalog.find_plane(plane_num)
      face = plane&.short_name&.to_s || name.to_s
      path = File.join(out_dir, "Essenfont-#{face}.ttf")
      stitcher.write_to(path, format: :ttf, subfont: name)
      puts "  #{face}: #{File.size(path)} bytes"
    end
  end

  def dump_cp_map(out_dir:, cp_map:)
    path = File.join(out_dir, "cp_map.json")
    File.write(path, JSON.pretty_generate(cp_map.donor_labels))
  end

  # ── WOFF + WOFF2 encoding via fontisan Ruby API (no CLI) ──

  def encode_woffs(out_dir:)
    puts "→ encoding per-plane WOFF + WOFF2"
    PLANES.each do |p|
      ttf = File.join(out_dir, "Essenfont-#{p}.ttf")
      next unless File.exist?(ttf)

      font = Fontisan::FontLoader.load(ttf)

      woff = Fontisan::Converters::WoffWriter.new.convert(font)
      File.binwrite(File.join(out_dir, "Essenfont-#{p}.woff"), woff)

      woff2 = Fontisan::Converters::Woff2Encoder.new.convert(font)
      File.binwrite(File.join(out_dir, "Essenfont-#{p}.woff2"), woff2[:woff2_binary])
      puts "  #{p}: woff + woff2 encoded"
    end
  end

  # ── Coverage manifest (in-process, captures stdout) ──

  def emit_coverage_manifest(out_dir:)
    puts "→ emitting coverage manifest"
    catalog = Essenfont::UcodeRef.catalog
    assigned = Essenfont::UcodeRef.assigned_count

    subfonts = []
    total_cps = 0
    catalog.all_planes.each do |plane|
      next unless plane.short_name
      file = "Essenfont-#{plane.short_name}.ttf"
      path = File.join(out_dir, file)
      next unless File.exist?(path)

      face = Fontisan::FontLoader.load(path)
      glyphs = face.table("maxp")&.num_glyphs || 0
      cps = (face.table("cmap")&.unicode_mappings || {}).size
      total_cps += cps
      subfonts << { name: plane.short_name.to_s, plane: plane.number,
                    glyph_count: glyphs, codepoint_count: cps,
                    ttf_url: file, woff2_url: file.sub(".ttf", ".woff2") }
    end

    pct = (total_cps.to_f / assigned * 100).round(2)
    manifest = {
      unicode_version: catalog.version, essenfont_version: Essenfont::Otc::Version::STRING,
      released_at: Time.now.utc.iso8601, total_codepoints: total_cps,
      total_assigned: assigned, coverage_percent: pct, subfonts: subfonts
    }
    File.write(File.join(out_dir, "coverage.json"), JSON.pretty_generate(manifest))
  end

  # ── Provenance manifest (in-process) ──

  def emit_provenance(out_dir:)
    puts "→ emitting provenance manifest"
    cp_map_path = File.join(out_dir, "cp_map.json")
    return unless File.exist?(cp_map_path)

    cp_map = JSON.parse(File.read(cp_map_path))
                 .transform_values { |v| { label: v["label"].to_sym } }

    manifest_entries = Essenfont::Manifest.load
    donors_meta = manifest_entries.each_with_object({}) do |e, h|
      h[e.label] = { family: e.family, license: e.license, url: e.url, sha256: e.sha256 }
    end

    catalog = Essenfont::UcodeRef.catalog
    blocks_meta = catalog.all_blocks.each_with_object({}) do |b, h|
      cps = cp_map.keys.select { |cp| cp >= b.first_cp && cp <= b.last_cp }
      counts = cps.each_with_object(Hash.new(0)) { |cp, c| c[cp_map[cp][:label]] += 1 }
      h[b.id] = { first_cp: sprintf("0x%X", b.first_cp), last_cp: sprintf("0x%X", b.last_cp),
                  primary_donor: counts.max_by { |_, v| v }&.first,
                  donors: counts.keys, codepoint_count: cps.size }
    end

    data = {
      essenfont_version: Essenfont::Otc::Version::STRING,
      ucd_version: catalog.version, generated_at: Time.now.utc.iso8601,
      donor_count: donors_meta.size, codepoint_count: cp_map.size,
      donors: donors_meta, blocks: blocks_meta,
      codepoints: cp_map.transform_values { |v| { donor: v[:label] } }
    }
    json = JSON.generate(data)
    File.write(File.join(out_dir, "provenance.json"), json)
    Zlib::GzipWriter.open(File.join(out_dir, "provenance.json.gz")) { |gz| gz.write(json) }
    puts "  provenance: #{cp_map.size} cps, #{blocks_meta.size} blocks"
  end

  # ── License attribution pack (in-process) ──

  def emit_license_pack(out_dir:)
    puts "→ emitting license attribution pack"
    pack_dir = File.join(out_dir, "license-pack")
    FileUtils.mkdir_p(pack_dir)

    manifest = Essenfont::Manifest.load
    cp_map_path = File.join(out_dir, "cp_map.json")
    cps_by_donor = {}
    if File.exist?(cp_map_path)
      JSON.parse(File.read(cp_map_path))
          .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(cp, info), h|
            h[info["label"].to_sym] << cp.to_i(16)
          }
          .each { |k, v| cps_by_donor[k] = v }
    end

    # LICENSE-SOURCES.md
    out = ["# Essenfont license sources", "", "Assembled from #{manifest.size} donor fonts.", ""]
    manifest.each do |e|
      cps = cps_by_donor[e.label] || []
      out << "## #{e.family} (#{e.license})"
      out << "- Files: #{Array(e.file).join(', ')}"
      out << "- Covers: #{cps.size} codepoints"
      out << "- Source: #{e.url}" if e.url
      out << ""
    end
    File.write(File.join(pack_dir, "LICENSE-SOURCES.md"), out.join("\n"))

    # CSV
    require "csv"
    CSV.open(File.join(pack_dir, "license-overview.csv"), "wb") do |csv|
      csv << %w[donor family license covers_count first_cp last_cp source_url sha256]
      manifest.each do |e|
        cps = cps_by_donor[e.label] || []
        csv << [e.label, e.family, e.license, cps.size,
                cps.min&.then { |c| "0x#{c.to_s(16).upcase}" } || "",
                cps.max&.then { |c| "0x#{c.to_s(16).upcase}" } || "",
                e.url || "", e.sha256 || ""]
      end
    end

    # FSung-NC filter
    nc_labels = %i[fsung_m fsung_2 fsung_3 fsung_x]
    nc_cps = nc_labels.flat_map { |l| cps_by_donor[l] || [] }.sort.uniq
    File.write(File.join(pack_dir, "fsung-nc-filter.txt"),
               nc_cps.map { |cp| cp.to_s(16).upcase }.join("\n") + "\n")

    # Zip
    Zip::File.open(File.join(out_dir, "license-pack.zip"), Zip::File::CREATE) do |zip|
      Dir.children(pack_dir).each { |f| zip.add(f, File.join(pack_dir, f)) }
    end
    puts "  license-pack: #{manifest.size} donors, #{nc_cps.size} NC cps"
  end

  # ── Per-codepoint SVG exports (in-process) ──

  def emit_svg_exports(out_dir:)
    puts "→ emitting per-codepoint SVG exports"
    otc_path = File.join(out_dir, "Essenfont-Regular.ttc")
    svg_dir = File.join(out_dir, "svg-exports")
    return unless File.exist?(otc_path)

    font = Fontisan::FontLoader.load(otc_path)
    units_per_em = font.table("head")&.units_per_em || 1000
    svg_xml = Fontisan::Converters::SvgGenerator.new.convert(font)[:svg_xml]

    require "nokogiri"
    doc = Nokogiri::XML(svg_xml)
    glyphs = doc.css("glyph").select { |g| g["unicode"] }
    FileUtils.mkdir_p(svg_dir)

    index = {}
    glyphs.each do |glyph|
      path_d = glyph["d"]
      next if path_d.nil? || path_d.strip.empty?

      decode_unicode(glyph["unicode"]).each do |cp|
        hex = cp.to_s(16).upcase
        name = glyph["glyph-name"] || ""
        File.write(File.join(svg_dir, "U+#{hex}.svg"), render_one_svg(cp, name, path_d, units_per_em))
        index["U+#{hex}.svg"] = { cp: "0x#{hex}", name: name }
      end
    end

    File.write(File.join(svg_dir, "index.json"),
               JSON.pretty_generate(essenfont_version: Essenfont::Otc::Version::STRING,
                                    total_svgs: index.size, files: index))

    # Zip via rubyzip
    Zip::File.open(File.join(out_dir, "svg-exports.zip"), Zip::File::CREATE) do |zip|
      Dir.children(svg_dir).each { |f| zip.add(f, File.join(svg_dir, f)) }
    end
    puts "  SVG exports: #{index.size} glyphs"
  end

  def decode_unicode(text)
    return [] unless text
    decoded = text.gsub(/&#x([0-9A-Fa-f]+);/) { [$1.to_i(16)].pack("U") }
                  .gsub(/&#(\d+);/) { [$1.to_i].pack("U") }
    decoded.codepoints.to_a
  rescue StandardError
    []
  end

  def render_one_svg(cp, name, path_d, upem)
    hex = cp.to_s(16).upcase
    name_meta = name.empty? ? "" : "<name>#{name.gsub("<", "&lt;")}</name>\n          "
    <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{upem} #{upem}" width="#{upem}" height="#{upem}">
        <metadata>
          <codepoint>U+#{hex}</codepoint>
          #{name_meta}<essenfont-version>#{Essenfont::Otc::Version::STRING}</essenfont-version>
          <generated-at>#{Time.now.utc.iso8601}</generated-at>
        </metadata>
        <g transform="translate(0, #{upem}) scale(1, -1)"><path d="#{path_d}"/></g>
      </svg>
    SVG
  end

  # ── npm package (npm pack is the only necessary subprocess) ──

  def build_npm_package(out_dir:)
    puts "→ building npm package"
    npm_dir = File.join(out_dir, "npm")
    FileUtils.rm_rf(npm_dir)
    fonts_dir = File.join(npm_dir, "fonts")
    css_dir = File.join(npm_dir, "css")
    FileUtils.mkdir_p([fonts_dir, css_dir])

    version = Essenfont::Otc::Version::STRING

    # Stage WOFF2s
    PLANES.each do |p|
      src = File.join(out_dir, "Essenfont-#{p}.woff2")
      FileUtils.cp(src, File.join(fonts_dir, "Essenfont-#{p}.woff2")) if File.exist?(src)
    end

    # Emit CSS
    planes = [
      { key: :BMP, range: "U+0000-FFFF" }, { key: :SMP, range: "U+10000-1FFFF" },
      { key: :SIP, range: "U+20000-2FFFF" }, { key: :TIP, range: "U+30000-3FFFF" },
      { key: :SSP, range: "U+E0000-EFFFF" }
    ]
    planes.each do |p|
      File.write(File.join(css_dir, "essenfont-#{p[:key].to_s.downcase}.css"),
                 "@font-face {\n  font-family: 'Essenfont';\n  src: url('../fonts/Essenfont-#{p[:key]}.woff2') format('woff2');\n  font-display: swap;\n  unicode-range: #{p[:range]};\n}\n")
    end
    File.write(File.join(css_dir, "all.css"),
               planes.map { |p| "@import url('./essenfont-#{p[:key].to_s.downcase}.css');" }.join("\n") + "\n")

    # package.json
    spec = { name: "essenfont", version: version,
             description: "Universal Unicode 17 font",
             main: "css/all.css", files: %w[css fonts README.md],
             license: "OFL-1.1", homepage: "https://essenfont.github.io",
             repository: { type: "git", url: "https://github.com/essenfont/essenfont.git" },
             publishConfig: { access: "public" } }
    File.write(File.join(npm_dir, "package.json"), JSON.pretty_generate(spec))

    # README
    File.write(File.join(npm_dir, "README.md"), "# essenfont\n\nUniversal Unicode 17 font. v#{version}.\n")

    # npm pack (the only necessary subprocess — npm CLI is not a Ruby gem)
    Dir.chdir(npm_dir) { `npm pack` }
    puts "  npm package: v#{version}"
  end

  # ── SRI hashes (pure Ruby) ──

  def emit_sri_hashes(out_dir:)
    puts "→ emitting SRI hashes"
    File.open(File.join(out_dir, "sri.txt"), "w") do |f|
      PLANES.each do |p|
        %w[woff woff2].each do |ext|
          file = File.join(out_dir, "Essenfont-#{p}.#{ext}")
          next unless File.exist?(file)
          b64 = [Digest::SHA384.file(file).digest].pack("m0")
          f.puts "Essenfont-#{p}.#{ext}=sha384-#{b64}"
        end
      end
    end
  end

  # ── Release manifest (pure Ruby) ──

  def write_release_manifest(out_dir:)
    data = { essenfont_version: Essenfont::Otc::Version::STRING,
             ucd_version: Essenfont::UcodeRef.unicode_version,
             generated_at: Time.now.utc.iso8601,
             artifacts: Dir.children(out_dir).sort }
    File.write(File.join(out_dir, "release-manifest.json"), JSON.pretty_generate(data))
  end

  # ── Coverage gate (inline — same logic as build.rb) ──

  def validate_coverage_gates(manifest:, donors:)
    manifest.active.each do |entry|
      next unless donors[entry.label]
      next if donors[entry.label][:remap]

      (entry.covers || []).each do |block|
        range = Essenfont::UcodeRef.block_range(block)
        next unless range
        count = donors[entry.label][:coverage].keys.count { |cp| cp >= range[0] && cp <= range[1] }
        next if count.positive?

        warn "  warn: #{entry.label} covers:#{block} has 0 cps (skipped)"
      end
    end
  end

  # ── Helpers ──

  def setup_output_dir(out_dir)
    FileUtils.rm_rf(out_dir)
    FileUtils.mkdir_p(out_dir)
  end

  def parse_options(argv)
    options = { out_dir: "release", dry_run: false, skip_build: false }
    OptionParser.new do |opts|
      opts.banner = "Usage: release.rb [options]"
      opts.on("--out-dir=PATH") { |v| options[:out_dir] = v }
      opts.on("--dry-run") { options[:dry_run] = true }
      opts.on("--skip-build") { options[:skip_build] = true }
    end.parse!(argv)
    options
  end
  private_class_method :parse_options

  def list_artifacts(out_dir)
    Dir.children(out_dir).sort.each do |f|
      path = File.join(out_dir, f)
      size = File.directory?(path) ? "dir" : "#{File.size(path)} bytes"
      puts "  #{f} (#{size})"
    end
  end
end

require "time"

if ARGV.first == "publish"
  ARGV.shift
  token = ARGV.find { |a| a.start_with?("--token=") }&.split("=", 2)&.last
  ENV["NPM_TOKEN"] = token if token
  Dir.chdir("release/npm") do
    `npm config set //registry.npmjs.org/:_authToken #{ENV.fetch("NPM_TOKEN", "")}`
    system("npm publish --access public") || raise("npm publish failed")
  end
else
  ReleasePipeline.run(ARGV)
end
