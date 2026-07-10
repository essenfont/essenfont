#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit a coverage manifest for the website.
#
# Standalone entry point — delegates to Essenfont::Release::CoverageManifest.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "essenfont"

ROOT = File.expand_path("..", __dir__)
manifest = Essenfont::Release::CoverageManifest.build(out_dir: ROOT)
puts JSON.pretty_generate(manifest)
