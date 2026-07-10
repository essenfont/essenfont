#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify that a built Essenfont font is well-formed.
#
# Usage:
#   ruby scripts/verify.rb [Essenfont-Regular.ttf]

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "essenfont"
require "fontisan"

path = ARGV[0] || "Essenfont-Regular.ttf"

unless File.exist?(path)
  warn "FAIL  #{path} not found (run `ruby scripts/build.rb` first)"
  exit 1
end

puts "=== Verifying #{path} ==="
failures = Essenfont::Otc::Validator.check(path)

if failures.empty?
  font = Fontisan::FontLoader.load(path)
  puts "PASS  #{path} (#{font.table('maxp')&.num_glyphs || 0} glyphs)"
else
  failures.each { |f| puts "FAIL  #{f.message}" }
  exit 1
end
