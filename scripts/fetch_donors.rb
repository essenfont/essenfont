#!/usr/bin/env ruby
# frozen_string_literal: true

# fetch_donors.rb — acquire donor font files referenced in the
# manifest. Handles three patterns per donor entry:
#
#   1. Direct download:    url: https://...
#                           → save to file: path
#
#   2. ZIP-extract:        url_extract: https://...zip
#                           url_extract_member: ZIP-PATH/INNER.ttf
#                           → download ZIP, extract member, save to file: path
#
#   3. Local-only:         path_local_only: true (no url)
#                           → skip with warning (user must supply)
#
# After download, every file is verified against its manifest sha256
# (unless sha256 is "TBD" or nil). Existing files are NOT overwritten
# unless --force is given.
#
# Usage:
#   ruby scripts/fetch_donors.rb                  # all donors
#   ruby scripts/fetch_donors.rb --label fsung-m  # one donor
#   ruby scripts/fetch_donors.rb --force          # overwrite existing
#   ruby scripts/fetch_donors.rb --dry-run        # show what would happen

require "yaml"
require "digest"
require "optparse"
require "fileutils"
require "open-uri"
require "tempfile"
require "zip"

module EssenfontFetch
  MANIFEST_PATH = File.expand_path("../sources/manifest.yml", __dir__)
  DONOR_DIR = File.expand_path("../references/input-fonts", __dir__)

  def self.run(labels: nil, force: false, dry_run: false)
    manifest = YAML.safe_load_file(MANIFEST_PATH)
    donors = manifest["donors"] || []

    results = donors.filter_map do |entry|
      next if labels && !labels.include?(entry["label"])

      action = plan(entry)
      log_plan(action, dry_run: dry_run)
      next if dry_run

      execute(action, force: force)
    end

    summarize(results)
  end

  # Decide what to do for a donor entry.
  # @return [Hash] action descriptor
  def self.plan(entry)
    label = entry["label"]
    file = entry["file"]
    path = resolve(file)

    if entry["path_local_only"]
      return { kind: :local_only, label: label, file: file, reason: "path_local_only: true" }
    end

    if entry["url_extract"] && entry["url_extract_member"]
      return {
        kind: :zip_extract,
        label: label,
        file: file,
        path: path,
        url: entry["url_extract"],
        member: entry["url_extract_member"],
        sha256: entry["sha256"],
        already_present: path && File.exist?(path),
      }
    end

    if entry["url"]
      return {
        kind: :direct,
        label: label,
        file: file,
        path: path,
        url: entry["url"],
        sha256: entry["sha256"],
        already_present: path && File.exist?(path),
      }
    end

    { kind: :no_source, label: label, file: file,
      reason: "no url, no url_extract; not path_local_only" }
  end

  def self.log_plan(action, dry_run:)
    case action[:kind]
    when :direct
      puts "[#{dry_run ? 'plan' : 'fetch'}] #{action[:label]}: download #{action[:url]}"
      puts "    -> #{action[:file]}#{" (exists)" if action[:already_present]}"
    when :zip_extract
      puts "[#{dry_run ? 'plan' : 'fetch'}] #{action[:label]}: download #{action[:url]}"
      puts "    extract: #{action[:member]}"
      puts "    -> #{action[:file]}#{" (exists)" if action[:already_present]}"
    when :local_only
      puts "[skip] #{action[:label]}: local-only — user must supply #{action[:file]}"
    when :no_source
      puts "[skip] #{action[:label]}: no source declared (#{action[:reason]})"
    end
  end

  # Execute the fetch. Returns {label:, status:, path:} for summarize.
  def self.execute(action, force:)
    case action[:kind]
    when :local_only, :no_source
      { label: action[:label], status: "skipped", path: nil }
    when :direct, :zip_extract
      download_and_place(action, force: force)
    end
  end

  def self.download_and_place(action, force:)
    out_path = File.join(DONOR_DIR, File.basename(action[:file]))
    FileUtils.mkdir_p(File.dirname(out_path))

    if File.exist?(out_path) && !force
      existing_sha = Digest::SHA256.file(out_path).hexdigest
      if action[:sha256] && action[:sha256] != "TBD" && existing_sha == action[:sha256].downcase
        puts "  [keep] #{action[:label]} — sha256 matches manifest"
        return { label: action[:label], status: "kept", path: out_path }
      end
      puts "  [keep] #{action[:label]} — exists (use --force to overwrite)"
      return { label: action[:label], status: "kept", path: out_path }
    end

    tmp = Tempfile.new(["essenfont-fetch-", ".bin"])
    begin
      puts "  downloading #{action[:url]} ..."
      URI.open(action[:url]) do |io|
        while (chunk = io.read(64 * 1024))
          tmp.write(chunk)
        end
      end
      tmp.flush

      if action[:kind] == :zip_extract
        extract_member(tmp.path, action[:member], out_path)
      else
        FileUtils.mv(tmp.path, out_path)
        tmp = nil
      end

      verify_sha256!(out_path, action[:sha256], action[:label])
      puts "  [ok]   #{action[:label]} -> #{out_path}"
      { label: action[:label], status: "fetched", path: out_path }
    rescue StandardError => e
      puts "  [FAIL] #{action[:label]}: #{e.class}: #{e.message}"
      { label: action[:label], status: "failed", path: nil, error: e.message }
    ensure
      tmp&.unlink
    end
  end

  # Extract a single member from a ZIP archive to a destination path.
  def self.extract_member(zip_path, member, dest_path)
    Zip::File.open(zip_path) do |zf|
      entry = zf.find_entry(member)
      raise "ZIP member not found: #{member}" if entry.nil?
      entry.extract(dest_path)
    end
  end

  def self.verify_sha256!(path, expected, label)
    return if expected.nil? || expected == "TBD"

    actual = Digest::SHA256.file(path).hexdigest
    if actual != expected.downcase
      File.unlink(path)
      raise "sha256 mismatch: expected #{expected[0..15]}…, got #{actual[0..15]}…"
    end
  end

  def self.resolve(file)
    return file if File.exist?(file)
    candidate = File.join(DONOR_DIR, File.basename(file))
    return candidate if File.exist?(candidate)
    nil
  end

  def self.summarize(results)
    counts = results.group_by { |r| r[:status] }.transform_values(&:size)
    puts ""
    puts "=== Summary ==="
    counts.each { |status, n| puts "  #{status}: #{n}" }
    failures = results.count { |r| r[:status] == "failed" }
    exit 1 unless failures.zero?
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { force: false, dry_run: false, labels: nil }
  OptionParser.new do |opts|
    opts.banner = "Usage: fetch_donors.rb [options]"
    opts.on("--label=LABEL", "only fetch the named donor (repeatable)") { |v| (options[:labels] ||= []) << v }
    opts.on("--force", "overwrite existing files with matching sha256") { options[:force] = true }
    opts.on("--dry-run", "show what would happen without downloading") { options[:dry_run] = true }
  end.parse!

  EssenfontFetch.run(labels: options[:labels], force: options[:force],
                     dry_run: options[:dry_run])
end