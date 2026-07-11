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

    cp_map = build_fonts(out_dir: options[:out_dir], skip: options[:skip_build])
    puts "→ encoding per-plane WOFF + WOFF2"
    Essenfont::Release::WoffEncoder.encode(out_dir: options[:out_dir])
    puts "→ emitting coverage manifest"
    Essenfont::Release::CoverageManifest.emit(out_dir: options[:out_dir])
    puts "→ emitting provenance"
    Essenfont::Release::Provenance.emit(out_dir: options[:out_dir], cp_map: cp_map)
    puts "→ emitting license pack"
    Essenfont::Release::LicensePack.emit(out_dir: options[:out_dir], cp_map: cp_map)
    emit_svg_exports(out_dir: options[:out_dir])
    puts "→ building npm package"
    Essenfont::Release::NpmPackage.build(out_dir: options[:out_dir])
    puts "→ emitting SRI hashes"
    Essenfont::Release::SriHashes.emit(out_dir: options[:out_dir])
    puts "→ writing release manifest"
    Essenfont::Release::ManifestWriter.emit(out_dir: options[:out_dir])

    puts "=== Done. Artifacts in #{options[:out_dir]}/ ==="
    list_artifacts(options[:out_dir])
  end

  # ── Build: OTC + per-plane TTFs (both in-process) ──

  def build_fonts(out_dir:, skip:)
    return nil if skip

    ENV["ESSENFONT_DUMP_CP_MAP"] = "1"

    puts "→ loading manifest + donors"
    manifest = Essenfont::Manifest.load
    donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
    raise "no donors loaded" if donors.empty?

    validate_coverage_gates(manifest:, donors:)

    cp_map = Essenfont::CpMap.build_from(donors)
    puts "  cp_map: #{cp_map.size} codepoints"

    cp_map.dump_json(File.join(out_dir, "cp_map.json"))

    puts "→ building OTC (CFF2 outlines)"
    result = Essenfont::Otc::Build.new(
      cp_map: cp_map, donors: donors, subfont_format: :otf2
    ).call(output_path: File.join(out_dir, "Essenfont-Regular.otc"))
    puts "  OTC: #{result.bytes} bytes, #{result.subfont_count} faces"

    puts "→ building per-plane TTFs"
    build = Essenfont::Otc::Build.new(cp_map: cp_map, donors: donors, subfont_format: :ttf)
    results = build.write_per_plane_ttfs(out_dir: out_dir)
    results.each { |r| puts "  #{r[:name]}: #{r[:bytes]} bytes" }

    cp_map
  end

  # ── Per-codepoint SVG exports (cached, delegates to library) ──

  def emit_svg_exports(out_dir:)
    puts "→ emitting per-codepoint SVG exports"
    otc_path = File.join(out_dir, "Essenfont-Regular.otc")
    svg_dir = File.join(out_dir, "svg-exports")
    return unless File.exist?(otc_path)

    # Cache: SVGs are derived solely from the OTC binary.
    otc_sha = Digest::SHA256.file(otc_path).hexdigest[0, 16]
    cache = Essenfont::BuildCache.new
    cached = cache.fetch_or_build_file("otc-#{otc_sha}", "svg-exports", svg_dir) do
      Essenfont::Release::SvgExports.emit(out_dir: svg_dir, font_path: otc_path)
    end
    puts "  svg-exports: #{cached ? 'from cache' : 'fresh build'}"
  end

  # ── Coverage gate (shared with scripts/build.rb) ──

  def validate_coverage_gates(manifest:, donors:)
    Essenfont::CoverageGate.new(manifest:, donors:).validate!
  end

  # ── Helpers ──

  def setup_output_dir(out_dir)
    FileUtils.rm_rf(out_dir)
    FileUtils.mkdir_p(out_dir)
  end

  def parse_options(argv)
    options = { out_dir: "release", skip_build: false }
    OptionParser.new do |opts|
      opts.banner = "Usage: release.rb [options]"
      opts.on("--out-dir=PATH") { |v| options[:out_dir] = v }
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
  Dir.chdir("release/npm") do
    system("npm publish --provenance --access public") || raise("npm publish failed")
  end
else
  ReleasePipeline.run(ARGV)
end
