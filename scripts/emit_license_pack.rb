#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit a license attribution pack for the current release.
#
# Standalone entry point — loads cp_map.json from the repo root, then
# delegates to Essenfont::Release::LicensePack.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "essenfont"

ROOT = File.expand_path("..", __dir__)

cp_map_path = File.join(ROOT, "cp_map.json")
cp_map = nil
if File.exist?(cp_map_path)
  raw = JSON.parse(File.read(cp_map_path))
  cp_map = Essenfont::CpMap.new(
    raw.transform_values { |v| { label: v["label"].to_sym, gid: 0 } }
  )
else
  warn "NOTE: cp_map.json not found — block-level summary only. " \
       "Run build.rb with ESSENFONT_DUMP_CP_MAP=1 for per-cp attribution."
end

Essenfont::Release::LicensePack.emit(out_dir: ROOT, cp_map: cp_map)
