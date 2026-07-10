#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit per-codepoint + per-block donor provenance for the website.
#
# Standalone entry point — loads cp_map.json from the repo root, then
# delegates to Essenfont::Release::Provenance.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "essenfont"

ROOT = File.expand_path("..", __dir__)

cp_map_path = File.join(ROOT, "cp_map.json")
unless File.exist?(cp_map_path)
  warn "cp_map.json not found at #{cp_map_path}. " \
       "Run build.rb with ESSENFONT_DUMP_CP_MAP=1 first."
  exit 1
end

# Reconstruct a CpMap from the dumped donor_labels JSON.
raw = JSON.parse(File.read(cp_map_path))
cp_map = Essenfont::CpMap.new(
  raw.transform_values { |v| { label: v["label"].to_sym, gid: 0 } }
)

Essenfont::Release::Provenance.emit(out_dir: ROOT, cp_map: cp_map)
