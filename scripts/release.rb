#!/usr/bin/env ruby
# frozen_string_literal: true

# Single entry point for the release pipeline. Replaces 12 inline YAML
# shell steps in .github/workflows/release.yml.
#
# Usage:
#   ruby scripts/release.rb                  # full release pipeline
#   ruby scripts/release.rb --dry-run        # build but skip publish + upload
#   ruby scripts/release.rb --skip-build     # only emit manifests + pack
#   ruby scripts/release.rb publish --token  # npm publish only
#
# Outputs land in release/ unless --out-dir overrides. The release.yml
# workflow uploads everything under release/ to the GitHub Release.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "optparse"
require "fileutils"
require "digest"
require "zip"
require "json"
require "essenfont"

module ReleasePipeline
  PLANES = %i[BMP SMP SIP TIP SSP].freeze

  module_function

  def run(argv)
    options = parse_options(argv)
    setup_output_dir(options[:out_dir])

    puts "=== Essenfont release pipeline v#{Essenfont::Otc::Version::STRING} ==="
    puts "  out dir: #{options[:out_dir]}"
    puts "  dry run: #{options[:dry_run]}"

    build_otc(out_dir: options[:out_dir], skip: options[:skip_build])
    build_per_plane_ttfs(out_dir: options[:out_dir], skip: options[:skip_build])
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

  def self.parse_options(argv)
    options = { out_dir: "release", dry_run: false, skip_build: false }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: release.rb [options]"
      opts.on("--out-dir=PATH", "output directory (default: release/)") { |v| options[:out_dir] = v }
      opts.on("--dry-run", "build but skip publish + upload") { options[:dry_run] = true }
      opts.on("--skip-build", "skip build steps (use existing OTC + per-plane TTFs)") { options[:skip_build] = true }
    end
    parser.parse!(argv)
    options
  end
  private_class_method :parse_options

  def self.run_build(format:)
    ENV["ESSENFONT_DUMP_CP_MAP"] = "1"
    load File.expand_path("build.rb", __dir__)
    puts "→ EssenfontBuild.run(format: #{format})"
    EssenfontBuild.run(format: format)
  rescue => e
    warn "BUILD FAILED: #{e.class}: #{e.message}"
    warn e.backtrace.first(15).join("\n")
    raise
  end
  private_class_method :run_build

  def self.setup_output_dir(out_dir)
    FileUtils.rm_rf(out_dir)
    FileUtils.mkdir_p(out_dir)
  end
  private_class_method :setup_output_dir

  def self.build_otc(out_dir:, skip:)
    return if skip

    puts "→ building OTC (glyf) → TTC container"
    run_build(format: :otc)
    FileUtils.mv("Essenfont-Regular.ttc", File.join(out_dir, "Essenfont-Regular.ttc"))
    FileUtils.cp("cp_map.json", File.join(out_dir, "cp_map.json")) if File.exist?("cp_map.json")
  end
  private_class_method :build_otc

  def self.build_per_plane_ttfs(out_dir:, skip:)
    return if skip

    puts "→ building per-plane TTFs"
    run_build(format: :"ttf-per-plane")
    PLANES.each do |p|
      src = "Essenfont-#{p}.ttf"
      FileUtils.mv(src, File.join(out_dir, src)) if File.exist?(src)
    end
  end
  private_class_method :build_per_plane_ttfs

  def self.encode_woffs(out_dir:)
    puts "→ encoding per-plane WOFF + WOFF2"
    PLANES.each do |p|
      ttf = File.join(out_dir, "Essenfont-#{p}.ttf")
      next unless File.exist?(ttf)

      base = File.join(out_dir, "Essenfont-#{p}")
      ok = system("bundle exec fontisan convert #{ttf} --to woff,woff2 --output #{base}")
      raise(Essenfont::Otc::Errors::BuildError, "WOFF encode failed for #{p}") unless ok
    end
  end
  private_class_method :encode_woffs

  def self.emit_coverage_manifest(out_dir:)
    puts "→ emitting coverage manifest"
    out = File.join(out_dir, "coverage.json")
    File.write(out, `bundle exec ruby scripts/emit_coverage_manifest.rb`)
  end
  private_class_method :emit_coverage_manifest

  def self.emit_provenance(out_dir:)
    puts "→ emitting provenance manifest"
    FileUtils.cp("cp_map.json", ".") if File.exist?(File.join(out_dir, "cp_map.json"))
    system("bundle exec ruby scripts/emit_provenance.rb") &&
      FileUtils.mv("provenance.json", File.join(out_dir, "provenance.json")) &&
      FileUtils.mv("provenance.json.gz", File.join(out_dir, "provenance.json.gz"))
  end
  private_class_method :emit_provenance

  def self.emit_license_pack(out_dir:)
    puts "→ emitting license attribution pack"
    system("bundle exec ruby scripts/emit_license_pack.rb")
    FileUtils.mv("license-pack", File.join(out_dir, "license-pack")) if File.directory?("license-pack")
    FileUtils.mv("license-pack.zip", File.join(out_dir, "license-pack.zip")) if File.exist?("license-pack.zip")
  end
  private_class_method :emit_license_pack

  def self.emit_svg_exports(out_dir:)
    puts "→ emitting per-codepoint SVG exports"
    otc_path = File.join(out_dir, "Essenfont-Regular.ttc")
    svg_dir = File.join(out_dir, "svg-exports")
    cp_map_path = File.join(out_dir, "cp_map.json")
    env = { "DONOR_MAP" => cp_map_path }
    ok = system(env, "bundle exec ruby scripts/emit_svg_exports.rb #{otc_path} #{svg_dir}")
    raise(Essenfont::Otc::Errors::BuildError, "SVG export failed") unless ok

    return unless File.directory?(svg_dir)

    Dir.chdir(out_dir) do
      system("cd svg-exports && zip -qr svg-exports.zip .")
    end
  end
  private_class_method :emit_svg_exports

  def self.build_npm_package(out_dir:)
    puts "→ building npm package"
    # npm/ directory is produced in the repo root by build_npm_package.rb
    FileUtils.rm_rf("npm") if File.directory?("npm")
    system("bundle exec ruby scripts/build_npm_package.rb")
    return unless File.directory?("npm")

    FileUtils.mv("npm", File.join(out_dir, "npm"))
    Dir.chdir(File.join(out_dir, "npm")) { system("npm pack") }
  end
  private_class_method :build_npm_package

  def self.emit_sri_hashes(out_dir:)
    puts "→ emitting SRI hashes"
    sri_path = File.join(out_dir, "sri.txt")
    File.open(sri_path, "w") do |f|
      PLANES.each do |p|
        %w[woff woff2].each do |ext|
          file = File.join(out_dir, "Essenfont-#{p}.#{ext}")
          next unless File.exist?(file)

          hash = Digest::SHA384.file(file).digest
          b64 = [hash].pack("m0")
          f.puts "Essenfont-#{p}.#{ext}=sha384-#{b64}"
        end
      end
    end
  end
  private_class_method :emit_sri_hashes

  def self.write_release_manifest(out_dir:)
    manifest = {
      essenfont_version: Essenfont::Otc::Version::STRING,
      ucd_version: Essenfont::UcodeRef.unicode_version,
      generated_at: Time.now.utc.iso8601,
      artifacts: Dir.children(out_dir).sort
    }
    File.write(File.join(out_dir, "release-manifest.json"), JSON.pretty_generate(manifest))
  end
  private_class_method :write_release_manifest

  def self.list_artifacts(out_dir)
    Dir.children(out_dir).sort.each do |f|
      path = File.join(out_dir, f)
      size = File.directory?(path) ? "dir" : "#{File.size(path)} bytes"
      puts "  #{f} (#{size})"
    end
  end
  private_class_method :list_artifacts
end

require "time"

if ARGV.first == "publish"
  # `ruby scripts/release.rb publish --token <npm-token>` — npm publish only.
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
