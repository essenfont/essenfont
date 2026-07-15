#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate manifest entries for all unregistered Noto fonts on disk.
# Run: ruby scripts/gen-donor-entries.rb >> sources/manifest.yml

require "digest"
require "fontisan"

DONOR_DIR = "references/input-fonts"
manifest_text = File.read("sources/manifest.yml")
registered = manifest_text.scan(/file: .+\/(.+)/).flatten.to_set

# Map codepoints → block IDs using the font's cmap
def blocks_covered(font)
  cmap = font.table("cmap")&.unicode_mappings || {}
  return [] if cmap.empty?
  # Load ucode blocks
  require "essenfont"
  catalog = Essenfont::UcodeRef.catalog
  block_map = {}
  catalog.all_blocks.each { |b| (b.first_cp..b.last_cp).each { |cp| (block_map[cp] ||= []) << b } }
  blocks = Set.new
  cmap.keys.each { |cp| block_map[cp]&.each { |b| blocks << b } }
  blocks.to_a
end

entries = []
Dir.glob("#{DONOR_DIR}/Noto*.ttf").sort.each do |path|
  basename = File.basename(path)
  next if registered.include?(basename)
  next if basename == "NotoColorEmoji.ttf" || basename == "NotoEmoji-Regular.ttf"

  begin
    font = Fontisan::FontLoader.load(path)
    blocks = blocks_covered(font)
    next if blocks.empty?

    # Derive label from filename
    name = basename.sub(/\.ttf$/, "").sub("-Regular", "")
    label = name.gsub(/([A-Z])/, '_\1').sub(/^_/, "").downcase
    label = label.sub(/^noto_/, "noto-").gsub("_", "-")

    # Determine family name
    family = name.gsub(/([A-Z])/, ' \1').sub(/^ /, "").strip

    sha = Digest::SHA256.file(path).hexdigest

    # Get unique blocks this font covers (primary blocks, not punctuation)
    primary_blocks = blocks.reject { |b| ["General_Punctuation", "Geometric_Shapes", "Currency_Symbols"].include?(b.id) }
    covers = primary_blocks.map(&:id).sort

    entries << {
      label: label,
      file: "references/input-fonts/#{basename}",
      family: family,
      license: "OFL",
      sha256: sha,
      url: "https://fonts.google.com/noto",
      author: "Google (Noto Project)",
      covers: covers
    }
  rescue => e
    warn "  skip #{basename}: #{e.message[0..80]}"
  end
end

# Output as YAML
entries.each do |e|
  puts "  - label: #{e[:label]}"
  puts "    file: #{e[:file]}"
  puts "    family: #{e[:family]}"
  puts "    style: Regular"
  puts "    license: #{e[:license]}"
  puts "    sha256: \"#{e[:sha256]}\""
  puts "    url: #{e[:url]}"
  puts "    author: \"#{e[:author]}\""
  puts "    covers: [#{e[:covers].join(", ")}]"
  puts ""
end

warn "Generated #{entries.size} manifest entries"
